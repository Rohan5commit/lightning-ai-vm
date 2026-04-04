#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
import urllib.request
from pathlib import Path


DEFAULT_AUTH_URL = "https://api.lightning.ai"
DEFAULT_SESSION_NAME = "vm-automation"


def clean(value: str | None) -> str:
    return (value or "").strip()


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    payload: dict | None = None,
) -> dict:
    request_headers = dict(headers or {})
    data = None
    if payload is not None:
        request_headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, headers=request_headers, data=data, method=method)
    with urllib.request.urlopen(request) as response:
        raw = response.read().decode("utf-8", errors="replace")
    return json.loads(raw) if raw else {}


def login() -> str:
    username = clean(os.environ.get("LIGHTNING_USERNAME"))
    api_key = clean(os.environ.get("LIGHTNING_API_KEY"))
    if not username or not api_key:
        raise RuntimeError("Missing LIGHTNING_USERNAME or LIGHTNING_API_KEY.")
    payload = request_json(
        f"{DEFAULT_AUTH_URL}/v1/auth/login",
        method="POST",
        payload={"username": username, "apiKey": api_key},
    )
    token = clean(str(payload.get("token") or ""))
    if not token:
        raise RuntimeError("Lightning login did not return a token.")
    return token


def normalize_studio_id(value: str) -> str:
    studio = clean(value)
    if "@" in studio:
        studio = studio.split("@", 1)[0]
    if studio.startswith("s_"):
        studio = studio[2:]
    return studio


def load_status(path: str) -> dict:
    if not path:
        return {}
    return json.loads(Path(path).read_text())


def resolve_ids(args: argparse.Namespace) -> tuple[str, str]:
    status = load_status(clean(getattr(args, "status_file", "")))
    project_id = clean(getattr(args, "project_id", "")) or clean(status.get("project_id")) or clean(os.environ.get("LIGHTNING_PROJECT_ID"))
    studio_id = (
        clean(getattr(args, "studio_id", ""))
        or clean(status.get("studio_id"))
        or clean(os.environ.get("LIGHTNING_STUDIO_ID"))
        or clean(os.environ.get("LIGHTNING_VM_TARGET"))
    )
    studio_id = normalize_studio_id(studio_id)
    if not project_id:
        raise RuntimeError("Missing project id. Provide --project-id or a status file from lightning_vm_heal.py.")
    if not studio_id:
        raise RuntimeError("Missing studio id. Provide --studio-id, LIGHTNING_STUDIO_ID, or LIGHTNING_VM_TARGET.")
    return project_id, studio_id


def execute(token: str, project_id: str, studio_id: str, command: str, *, session_name: str, detached: bool = False) -> dict:
    return request_json(
        f"{DEFAULT_AUTH_URL}/v1/projects/{project_id}/cloudspaces/{studio_id}/execute",
        method="POST",
        headers={"Authorization": f"Bearer {token}"},
        payload={"command": command, "detached": detached, "sessionName": session_name},
    )


def keepalive(token: str, project_id: str, studio_id: str) -> dict:
    return request_json(
        f"{DEFAULT_AUTH_URL}/v1/projects/{project_id}/cloudspaces/{studio_id}/keep-alive",
        method="POST",
        headers={"Authorization": f"Bearer {token}"},
        payload={},
    )


def shell_write_command(local: Path, remote: str, token: str) -> str:
    content = local.read_text(encoding="utf-8")
    return f"cat > {shlex.quote(remote)} <<'{token}'\n{content}\n{token}\n"


def build_bootstrap_command(script_dir: Path) -> str:
    remote_tmp = "/tmp/nemoclaw-vm-automation"
    remote_install_dir = "/opt/nemoclaw-vm-automation"
    remote_studio_dir = "/home/zeus/content/.lightning_studio"

    transfers = [
        (script_dir.parent / "systemd" / "lightning-vm-keepalive.service", f"{remote_tmp}/lightning-vm-keepalive.service"),
        (script_dir / "vm_keepalive_loop.sh", f"{remote_tmp}/vm_keepalive_loop.sh"),
        (script_dir / "vm_snapshot_remote.py", f"{remote_tmp}/vm_snapshot_remote.py"),
        (script_dir.parent / "lightning_studio" / "on_start.sh", f"{remote_tmp}/on_start.sh"),
        (script_dir.parent / "lightning_studio" / "on_stop.sh", f"{remote_tmp}/on_stop.sh"),
    ]

    parts = [
        "set -euo pipefail",
        f"REMOTE_TMP={shlex.quote(remote_tmp)}",
        f"REMOTE_INSTALL_DIR={shlex.quote(remote_install_dir)}",
        f"REMOTE_STUDIO_DIR={shlex.quote(remote_studio_dir)}",
        'mkdir -p "$REMOTE_TMP" "$REMOTE_STUDIO_DIR"',
    ]
    for idx, (local, remote) in enumerate(transfers):
        parts.append(shell_write_command(local, remote, f"__VM_FILE_{idx}__"))
    parts.extend(
        [
            'sudo mkdir -p "$REMOTE_INSTALL_DIR"',
            'sudo install -m 0755 "$REMOTE_TMP/vm_keepalive_loop.sh" "$REMOTE_INSTALL_DIR/vm_keepalive_loop.sh"',
            'sudo install -m 0755 "$REMOTE_TMP/vm_snapshot_remote.py" "$REMOTE_INSTALL_DIR/vm_snapshot_remote.py"',
            'sudo install -m 0644 "$REMOTE_TMP/lightning-vm-keepalive.service" /etc/systemd/system/lightning-vm-keepalive.service',
            'install -m 0755 "$REMOTE_TMP/on_start.sh" "$REMOTE_STUDIO_DIR/on_start.sh"',
            'install -m 0755 "$REMOTE_TMP/on_stop.sh" "$REMOTE_STUDIO_DIR/on_stop.sh"',
            "sudo systemctl daemon-reload",
            "sudo systemctl enable --now lightning-vm-keepalive.service",
            "sudo systemctl restart lightning-vm-keepalive.service",
            'bash "$REMOTE_STUDIO_DIR/on_start.sh" || true',
            "systemctl is-active lightning-vm-keepalive.service",
        ]
    )
    return "\n".join(parts)


def cmd_exec(args: argparse.Namespace) -> int:
    project_id, studio_id = resolve_ids(args)
    token = login()
    data = execute(
        token,
        project_id,
        studio_id,
        args.command,
        session_name=args.session_name or DEFAULT_SESSION_NAME,
        detached=bool(args.detached),
    )
    output = data.get("output") or ""
    if output:
        sys.stdout.write(output)
        if not output.endswith("\n"):
            sys.stdout.write("\n")
    return int(data.get("exitCode") or 0)


def cmd_keepalive(args: argparse.Namespace) -> int:
    project_id, studio_id = resolve_ids(args)
    token = login()
    data = keepalive(token, project_id, studio_id)
    print(json.dumps(data, indent=2))
    return 0


def cmd_bootstrap(args: argparse.Namespace) -> int:
    project_id, studio_id = resolve_ids(args)
    token = login()
    data = execute(token, project_id, studio_id, build_bootstrap_command(Path(__file__).resolve().parent), session_name="vm-bootstrap")
    output = data.get("output") or ""
    if output:
        sys.stdout.write(output)
        if not output.endswith("\n"):
            sys.stdout.write("\n")
    return int(data.get("exitCode") or 0)


def cmd_snapshot(args: argparse.Namespace) -> int:
    project_id, studio_id = resolve_ids(args)
    token = login()
    data = execute(
        token,
        project_id,
        studio_id,
        "python3 /opt/nemoclaw-vm-automation/vm_snapshot_remote.py",
        session_name="vm-snapshot",
    )
    output = data.get("output") or ""
    if output:
        sys.stdout.write(output)
        if not output.endswith("\n"):
            sys.stdout.write("\n")
    return int(data.get("exitCode") or 0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    def add_id_args(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--status-file", default=os.environ.get("LIGHTNING_VM_STATUS_FILE", ""))
        subparser.add_argument("--project-id", default="")
        subparser.add_argument("--studio-id", default="")

    keepalive_parser = subparsers.add_parser("keepalive")
    add_id_args(keepalive_parser)
    keepalive_parser.set_defaults(func=cmd_keepalive)

    exec_parser = subparsers.add_parser("exec")
    add_id_args(exec_parser)
    exec_parser.add_argument("--command", required=True)
    exec_parser.add_argument("--session-name", default=DEFAULT_SESSION_NAME)
    exec_parser.add_argument("--detached", action="store_true")
    exec_parser.set_defaults(func=cmd_exec)

    bootstrap_parser = subparsers.add_parser("bootstrap")
    add_id_args(bootstrap_parser)
    bootstrap_parser.set_defaults(func=cmd_bootstrap)

    snapshot_parser = subparsers.add_parser("snapshot")
    add_id_args(snapshot_parser)
    snapshot_parser.set_defaults(func=cmd_snapshot)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
