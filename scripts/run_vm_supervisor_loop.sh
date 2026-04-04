#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUPERVISOR_MINUTES="${SUPERVISOR_MINUTES:-235}"
SUPERVISOR_INTERVAL_SECONDS="${SUPERVISOR_INTERVAL_SECONDS:-240}"

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

pulse_once() {
  python "$SCRIPT_DIR/lightning_vm_heal.py" --restart-if-needed --out vm-supervisor-status.json
  export LIGHTNING_VM_STATUS_FILE=vm-supervisor-status.json
  if ! bash "$SCRIPT_DIR/pulse_vm_keepalive.sh" > vm-supervisor-snapshot.json; then
    bootstrap_once
    bash "$SCRIPT_DIR/pulse_vm_keepalive.sh" > vm-supervisor-snapshot.json
  fi
  if ! validate_snapshot_json vm-supervisor-snapshot.json; then
    python "$SCRIPT_DIR/lightning_vm_remote.py" snapshot --status-file vm-supervisor-status.json > vm-supervisor-snapshot.json
  fi
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

python "$SCRIPT_DIR/lightning_vm_heal.py" --restart-if-needed --out vm-supervisor-status.json
export LIGHTNING_VM_STATUS_FILE=vm-supervisor-status.json
bootstrap_once

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
