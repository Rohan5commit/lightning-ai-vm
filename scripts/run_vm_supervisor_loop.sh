#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUPERVISOR_MINUTES="${SUPERVISOR_MINUTES:-235}"
SUPERVISOR_INTERVAL_SECONDS="${SUPERVISOR_INTERVAL_SECONDS:-240}"
RUNNING_PHASE="CLOUD_SPACE_INSTANCE_STATE_RUNNING"

deadline_epoch="$(( $(date +%s) + SUPERVISOR_MINUTES * 60 ))"

validate_snapshot_json() {
  python - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8").strip()
if not raw:
    raise SystemExit(1)
json.loads(raw)
PY
}

bootstrap_once() {
  export LIGHTNING_VM_STATUS_FILE="${LIGHTNING_VM_STATUS_FILE:-vm-supervisor-status.json}"
  bash "$SCRIPT_DIR/bootstrap_vm_keepalive.sh"
}

refresh_status() {
  python "$SCRIPT_DIR/lightning_vm_heal.py" --out vm-supervisor-status.json
  export LIGHTNING_VM_STATUS_FILE=vm-supervisor-status.json
}

current_phase() {
  python - <<'PY'
import json
from pathlib import Path

status = json.loads(Path("vm-supervisor-status.json").read_text())
print(status.get("instance_phase") or "unknown")
PY
}

write_degraded_snapshot() {
  python - <<'PY'
import json
from pathlib import Path

status = json.loads(Path("vm-supervisor-status.json").read_text())
payload = {
    "keepalive_service": {"active": False},
    "keepalive_heartbeat": {"exists": False},
    "nemoclaw_health": {
        "ok": False,
        "needs_recovery": True,
        "error": status.get("instance_phase") or "unknown",
    },
}
Path("vm-supervisor-snapshot.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

capture_snapshot() {
  if ! bash "$SCRIPT_DIR/pulse_vm_keepalive.sh" > vm-supervisor-snapshot.json; then
    if ! python "$SCRIPT_DIR/lightning_vm_remote.py" snapshot --status-file vm-supervisor-status.json > vm-supervisor-snapshot.json; then
      bootstrap_once || return 1
      if ! bash "$SCRIPT_DIR/pulse_vm_keepalive.sh" > vm-supervisor-snapshot.json; then
        python "$SCRIPT_DIR/lightning_vm_remote.py" snapshot --status-file vm-supervisor-status.json > vm-supervisor-snapshot.json || return 1
      fi
    fi
  fi
  if ! validate_snapshot_json vm-supervisor-snapshot.json; then
    python "$SCRIPT_DIR/lightning_vm_remote.py" snapshot --status-file vm-supervisor-status.json > vm-supervisor-snapshot.json || return 1
  fi
}

print_summary() {
  python - <<'PY'
import json
from pathlib import Path

status = json.loads(Path("vm-supervisor-status.json").read_text())
snapshot = json.loads(Path("vm-supervisor-snapshot.json").read_text())
print(
    f"studio_id={status.get('studio_id')} action={status.get('action')} "
    f"phase={status.get('instance_phase')} keepalive_active={snapshot['keepalive_service']['active']} "
    f"health_ok={snapshot['nemoclaw_health'].get('ok')} needs_recovery={snapshot['nemoclaw_health'].get('needs_recovery')}"
)
PY
}

pulse_once() {
  refresh_status
  phase="$(current_phase)"
  if [ "$phase" != "$RUNNING_PHASE" ]; then
    write_degraded_snapshot
    print_summary
    echo "VM Supervisor: studio is not running; skipping restart and waiting for the 10-minute keepalive workflow to heal it."
    return 0
  fi
  if ! capture_snapshot; then
    write_degraded_snapshot
    print_summary
    echo "VM Supervisor: non-fatal remote pulse/snapshot failure; continuing loop."
    return 0
  fi
  print_summary
}

refresh_status
if [ "$(current_phase)" = "$RUNNING_PHASE" ]; then
  bootstrap_once || true
else
  write_degraded_snapshot
  print_summary
  echo "VM Supervisor: studio is not running at startup; skipping bootstrap until the keepalive workflow heals it."
fi

while true; do
  pulse_once
  now_epoch="$(date +%s)"
  if [ "$now_epoch" -ge "$deadline_epoch" ]; then
    break
  fi
  remaining="$(( deadline_epoch - now_epoch ))"
  sleep_seconds="$SUPERVISOR_INTERVAL_SECONDS"
  if [ "$remaining" -lt "$sleep_seconds" ]; then
    sleep_seconds="$remaining"
  fi
  if [ "$sleep_seconds" -gt 0 ]; then
    sleep "$sleep_seconds"
  fi
done
