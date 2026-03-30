#!/usr/bin/env python3
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib import request


def slurp_json(path: Path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception:
        return {"raw": path.read_text(errors="ignore")}


def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return {
        "code": proc.returncode,
        "stdout": (proc.stdout or "").strip(),
        "stderr": (proc.stderr or "").strip(),
    }


def http_json(url: str):
    try:
        with request.urlopen(url, timeout=10) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return json.loads(raw)
    except Exception as exc:
        return {"error": str(exc)}


base = Path("/teamspace/studios/this_studio/.lightning-checkpoints/nemoclaw-vm-keepalive")
payload = {
    "captured_at": datetime.now(timezone.utc).isoformat(),
    "keepalive_service": run(["systemctl", "is-active", "lightning-vm-keepalive.service"]),
    "keepalive_heartbeat": slurp_json(base / "heartbeat.json"),
    "nemoclaw_health": http_json("http://127.0.0.1:38080/healthz"),
}
print(json.dumps(payload, indent=2))
