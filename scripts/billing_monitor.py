#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import hmac
import html
import json
import os
import smtplib
import sqlite3
import ssl
import sys
import traceback
import urllib.parse
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from email.message import EmailMessage
from pathlib import Path
from typing import Any

import oci
from oci.usage_api.models import RequestSummarizedUsagesDetails


DB_PATH = Path(os.environ.get("BILLING_DB_PATH", "/var/lib/nemoclaw-billing/billing.sqlite3"))
STATE_DIR = Path(os.environ.get("BILLING_STATE_DIR", "/var/lib/nemoclaw-billing"))
BOARD_DIR = Path(os.environ.get("BILLING_BOARD_DIR", "/var/lib/nemoclaw-billing/www"))
LATEST_JSON = STATE_DIR / "latest.json"
LOG_JSON = STATE_DIR / "last-run.json"

ALERT_THRESHOLD = float(os.environ.get("BILLING_ALERT_THRESHOLD", "0.50"))
SMTP_HOST = os.environ.get("BILLING_SMTP_HOST", "smtp.gmail.com").strip()
SMTP_PORT = int(os.environ.get("BILLING_SMTP_PORT", "465"))
SMTP_USERNAME = os.environ.get("BILLING_SMTP_USERNAME", "").strip()
SMTP_PASSWORD = os.environ.get("BILLING_SMTP_PASSWORD", "").strip()
ALERT_EMAIL_TO = os.environ.get("BILLING_ALERT_EMAIL_TO", SMTP_USERNAME).strip()

OCI_CONFIG_PATH = os.environ.get("OCI_CONFIG_FILE", "/etc/nemoclaw-billing-monitor/oci_config")
OCI_PROFILE = os.environ.get("OCI_CONFIG_PROFILE", "DEFAULT")

ALIBABA_ACCESS_KEY_ID = os.environ.get("ALIBABA_ACCESS_KEY_ID", "").strip()
ALIBABA_ACCESS_KEY_SECRET = os.environ.get("ALIBABA_ACCESS_KEY_SECRET", "").strip()
ALIBABA_ENDPOINT = os.environ.get("ALIBABA_BILLING_ENDPOINT", "business.ap-southeast-1.aliyuncs.com").strip()


@dataclass
class ProviderTotal:
    provider: str
    total: float
    currency: str
    observed_at: str
    details: dict[str, Any]


def utcnow() -> datetime:
    return datetime.now(UTC)


def iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def month_start(dt: datetime) -> datetime:
    return dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def next_month_start(dt: datetime) -> datetime:
    if dt.month == 12:
        return dt.replace(year=dt.year + 1, month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
    return dt.replace(month=dt.month + 1, day=1, hour=0, minute=0, second=0, microsecond=0)


def ensure_dirs() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    BOARD_DIR.mkdir(parents=True, exist_ok=True)


def connect_db() -> sqlite3.Connection:
    ensure_dirs()
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        create table if not exists snapshots (
            id integer primary key autoincrement,
            provider text not null,
            observed_at text not null,
            currency text not null,
            total real not null,
            payload_json text not null
        )
        """
    )
    conn.execute(
        """
        create table if not exists alerts (
            id integer primary key autoincrement,
            provider text not null,
            sent_at text not null,
            previous_total real not null,
            new_total real not null,
            delta real not null,
            currency text not null,
            reason text not null
        )
        """
    )
    conn.commit()
    return conn


def oci_total() -> ProviderTotal:
    config = oci.config.from_file(OCI_CONFIG_PATH, OCI_PROFILE)
    client = oci.usage_api.UsageapiClient(config)
    start = month_start(utcnow())
    end = next_month_start(start)
    request = RequestSummarizedUsagesDetails(
        tenant_id=config["tenancy"],
        time_usage_started=iso(start),
        time_usage_ended=iso(end),
        granularity="MONTHLY",
        query_type="COST",
        is_aggregate_by_time=True,
        group_by=["service"],
    )
    response = client.request_summarized_usages(request)
    items = oci.util.to_dict(response.data).get("items", []) or []
    total = sum(float(item.get("attributed_cost") or 0.0) for item in items)
    currency = next((item.get("currency") for item in items if item.get("currency") and str(item.get("currency")).strip()), "SGD")
    return ProviderTotal(
        provider="oracle",
        total=round(total, 6),
        currency=str(currency).strip(),
        observed_at=iso(utcnow()),
        details={"items": items},
    )


def percent_encode(value: str) -> str:
    return urllib.parse.quote(value, safe="~")


def alibaba_signature(params: dict[str, str], secret: str) -> str:
    canonical = "&".join(f"{percent_encode(k)}={percent_encode(v)}" for k, v in sorted(params.items()))
    string_to_sign = f"GET&%2F&{percent_encode(canonical)}"
    digest = hmac.new(f"{secret}&".encode("utf-8"), string_to_sign.encode("utf-8"), hashlib.sha1).digest()
    return base64.b64encode(digest).decode("utf-8")


def alibaba_request(action: str, extra: dict[str, str]) -> dict[str, Any]:
    params = {
        "Action": action,
        "Format": "JSON",
        "Version": "2017-12-14",
        "AccessKeyId": ALIBABA_ACCESS_KEY_ID,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": iso(utcnow()),
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
    }
    params.update(extra)
    params["Signature"] = alibaba_signature(params, ALIBABA_ACCESS_KEY_SECRET)
    url = f"https://{ALIBABA_ENDPOINT}/?{urllib.parse.urlencode(params)}"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Alibaba API HTTP {exc.code}: {body}") from exc


def alibaba_item_amount(item: dict[str, Any]) -> float:
    preferred = [
        "PretaxGrossAmount",
        "PretaxAmount",
        "PaymentAmount",
        "CashAmount",
        "OutstandingAmount",
    ]
    for key in preferred:
        value = item.get(key)
        if value in (None, "", "null"):
            continue
        try:
            return float(value)
        except Exception:
            continue
    for key, value in item.items():
        if "Amount" not in key or value in (None, "", "null"):
            continue
        try:
            return float(value)
        except Exception:
            continue
    return 0.0


def alibaba_total() -> ProviderTotal:
    cycle = utcnow().strftime("%Y-%m")
    page = 1
    total = 0.0
    raw_items: list[dict[str, Any]] = []
    total_count = None
    while True:
        payload = alibaba_request(
            "QueryAccountBill",
            {
                "BillingCycle": cycle,
                "Granularity": "MONTHLY",
                "PageNum": str(page),
                "PageSize": "300",
                "IsGroupByProduct": "false",
            },
        )
        data = payload.get("Data", {}) or {}
        items = (((data.get("Items") or {}).get("Item")) or [])
        if isinstance(items, dict):
            items = [items]
        raw_items.extend(items)
        total += sum(alibaba_item_amount(item) for item in items)
        total_count = int(data.get("TotalCount") or len(raw_items) or 0)
        page_size = int(data.get("PageSize") or 300)
        if len(raw_items) >= total_count or not items or len(items) < page_size:
            break
        page += 1
    currency = "USD"
    for item in raw_items:
        for key in ("Currency", "CurrencyCode"):
            if item.get(key):
                currency = str(item[key]).strip()
                break
    return ProviderTotal(
        provider="alibaba",
        total=round(total, 6),
        currency=currency,
        observed_at=iso(utcnow()),
        details={"billing_cycle": cycle, "total_count": total_count, "items": raw_items},
    )


def latest_total(conn: sqlite3.Connection, provider: str) -> tuple[float | None, str | None]:
    row = conn.execute(
        "select total, currency from snapshots where provider = ? order by id desc limit 1",
        (provider,),
    ).fetchone()
    if not row:
        return None, None
    return float(row[0]), str(row[1])


def last_alert_total(conn: sqlite3.Connection, provider: str) -> float | None:
    row = conn.execute(
        "select new_total from alerts where provider = ? order by id desc limit 1",
        (provider,),
    ).fetchone()
    return float(row[0]) if row else None


def save_snapshot(conn: sqlite3.Connection, result: ProviderTotal) -> None:
    conn.execute(
        "insert into snapshots(provider, observed_at, currency, total, payload_json) values (?, ?, ?, ?, ?)",
        (result.provider, result.observed_at, result.currency, result.total, json.dumps(result.details)),
    )
    conn.commit()


def send_email(subject: str, body: str) -> None:
    if not (SMTP_HOST and SMTP_USERNAME and SMTP_PASSWORD and ALERT_EMAIL_TO):
        return
    message = EmailMessage()
    message["From"] = SMTP_USERNAME
    message["To"] = ALERT_EMAIL_TO
    message["Subject"] = subject
    message.set_content(body)
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=30) as client:
        client.login(SMTP_USERNAME, SMTP_PASSWORD)
        client.send_message(message)


def maybe_alert(conn: sqlite3.Connection, result: ProviderTotal) -> dict[str, Any] | None:
    previous_total, _ = latest_total(conn, result.provider)
    last_alerted = last_alert_total(conn, result.provider)
    baseline = last_alerted if last_alerted is not None else previous_total
    if baseline is None:
        return None
    delta = round(result.total - baseline, 6)
    if delta < ALERT_THRESHOLD:
        return None
    reason = f"{result.provider} bill increased by {result.currency} {delta:.2f} since the last alert."
    conn.execute(
        "insert into alerts(provider, sent_at, previous_total, new_total, delta, currency, reason) values (?, ?, ?, ?, ?, ?, ?)",
        (result.provider, iso(utcnow()), baseline, result.total, delta, result.currency, reason),
    )
    conn.commit()
    send_email(
        subject=f"[Billing Alert] {result.provider.title()} +{result.currency} {delta:.2f}",
        body=(
            f"Provider: {result.provider}\n"
            f"Previous alerted total: {result.currency} {baseline:.2f}\n"
            f"Current total: {result.currency} {result.total:.2f}\n"
            f"Delta: {result.currency} {delta:.2f}\n"
            f"Observed at: {result.observed_at}\n\n"
            "This monitor polls the providers every 15 minutes, but provider billing data is delayed and may not match card-settlement timing."
        ),
    )
    return {
        "provider": result.provider,
        "delta": delta,
        "currency": result.currency,
        "new_total": result.total,
    }


def write_board(conn: sqlite3.Connection, latest: dict[str, ProviderTotal], alerts: list[dict[str, Any]], errors: list[dict[str, Any]]) -> None:
    latest_rows = conn.execute(
        "select provider, observed_at, currency, total from snapshots order by id desc limit 20"
    ).fetchall()
    recent_alerts = conn.execute(
        "select provider, sent_at, currency, delta, previous_total, new_total, reason from alerts order by id desc limit 20"
    ).fetchall()
    latest_payload = {
        "generated_at": iso(utcnow()),
        "providers": {name: {"total": data.total, "currency": data.currency, "observed_at": data.observed_at} for name, data in latest.items()},
        "alerts": alerts,
        "errors": errors,
    }
    LATEST_JSON.write_text(json.dumps(latest_payload, indent=2) + "\n", encoding="utf-8")
    LOG_JSON.write_text(json.dumps({"latest": latest_payload, "recent_alerts": recent_alerts}, indent=2, default=str) + "\n", encoding="utf-8")

    def table(rows: list[tuple[Any, ...]]) -> str:
        body = []
        for row in rows:
            body.append("<tr>" + "".join(f"<td>{html.escape(str(cell))}</td>" for cell in row) + "</tr>")
        return "\n".join(body) or "<tr><td colspan='8'>No data yet</td></tr>"

    cards = []
    for name, data in latest.items():
        cards.append(
            f"""
            <div class="card">
              <h2>{html.escape(name.title())}</h2>
              <p class="value">{html.escape(data.currency)} {data.total:,.2f}</p>
              <p>Observed: {html.escape(data.observed_at)}</p>
            </div>
            """
        )
    if errors:
        cards.append(
            "<div class='card error'><h2>Errors</h2><pre>"
            + html.escape(json.dumps(errors, indent=2))
            + "</pre></div>"
        )

    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cloud Billing Board</title>
  <style>
    :root {{ --bg:#0f172a; --panel:#111827; --muted:#94a3b8; --text:#e5e7eb; --accent:#22c55e; --warn:#f59e0b; }}
    body {{ font-family: ui-sans-serif, system-ui, sans-serif; margin:0; background:linear-gradient(160deg,#0b1220,#111827); color:var(--text); }}
    main {{ max-width:1100px; margin:0 auto; padding:32px 20px 80px; }}
    h1 {{ margin:0 0 8px; font-size:32px; }}
    p.meta {{ color:var(--muted); margin:0 0 24px; }}
    .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:16px; margin-bottom:28px; }}
    .card {{ background:rgba(17,24,39,.92); border:1px solid rgba(148,163,184,.15); border-radius:16px; padding:18px; }}
    .card.error {{ border-color: rgba(245,158,11,.5); }}
    .value {{ font-size:28px; margin:8px 0; color:var(--accent); }}
    table {{ width:100%; border-collapse:collapse; background:rgba(17,24,39,.92); border-radius:16px; overflow:hidden; }}
    th,td {{ padding:12px 14px; border-bottom:1px solid rgba(148,163,184,.12); text-align:left; font-size:14px; }}
    th {{ color:var(--muted); font-weight:600; }}
    section {{ margin-top:24px; }}
    pre {{ white-space:pre-wrap; word-break:break-word; }}
  </style>
</head>
<body>
<main>
  <h1>Cloud Billing Board</h1>
  <p class="meta">Generated at {html.escape(iso(utcnow()))}. Poll interval: 15 minutes. Alerts trigger when a provider total rises by at least {ALERT_THRESHOLD:.2f} since the last alert.</p>
  <div class="grid">{''.join(cards) or '<div class="card"><p>No provider data yet</p></div>'}</div>
  <section>
    <h2>Recent Snapshots</h2>
    <table>
      <thead><tr><th>Provider</th><th>Observed</th><th>Currency</th><th>Total</th></tr></thead>
      <tbody>{table(latest_rows)}</tbody>
    </table>
  </section>
  <section>
    <h2>Recent Alerts</h2>
    <table>
      <thead><tr><th>Provider</th><th>Sent</th><th>Currency</th><th>Delta</th><th>Previous</th><th>New</th><th>Reason</th></tr></thead>
      <tbody>{table(recent_alerts)}</tbody>
    </table>
  </section>
</main>
</body>
</html>
"""
    (BOARD_DIR / "index.html").write_text(page, encoding="utf-8")
    (BOARD_DIR / "latest.json").write_text(json.dumps(latest_payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ensure_dirs()
    conn = connect_db()
    latest: dict[str, ProviderTotal] = {}
    alerts: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    providers = [oci_total]
    if ALIBABA_ACCESS_KEY_ID and ALIBABA_ACCESS_KEY_SECRET:
        providers.append(alibaba_total)

    for fn in providers:
        try:
            result = fn()
            latest[result.provider] = result
            alert = maybe_alert(conn, result)
            save_snapshot(conn, result)
            if alert:
                alerts.append(alert)
        except Exception as exc:
            errors.append(
                {
                    "provider": fn.__name__,
                    "error": str(exc),
                    "traceback": traceback.format_exc(limit=5),
                }
            )

    write_board(conn, latest, alerts, errors)
    if errors:
        print(json.dumps({"ok": False, "errors": errors, "providers": list(latest.keys())}, indent=2))
        return 1
    print(json.dumps({"ok": True, "providers": {k: {"total": v.total, "currency": v.currency} for k, v in latest.items()}, "alerts": alerts}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
