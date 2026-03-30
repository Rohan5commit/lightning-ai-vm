#!/usr/bin/env bash
set -euo pipefail

KEEPALIVE_DIR="${KEEPALIVE_DIR:-/teamspace/studios/this_studio/.lightning-checkpoints/nemoclaw-vm-keepalive}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-240}"
NEMOCLAW_DIR="${NEMOCLAW_DIR:-/home/zeus/content/workspace/NemoClaw}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:38080/healthz}"

mkdir -p "$KEEPALIVE_DIR"

write_json() {
  local path="$1"
  local kind="$2"
  python3 - "$path" "$kind" <<'PY'
import json
import os
import socket
import sys
from datetime import datetime, timezone

path, kind = sys.argv[1], sys.argv[2]
payload = {
    "kind": kind,
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "host": socket.gethostname(),
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY
}

while true; do
  write_json "$KEEPALIVE_DIR/heartbeat.json" "heartbeat"
  touch "$KEEPALIVE_DIR/.last-touch"
  curl -fsS "$HEALTH_URL" >/dev/null 2>&1 || true
  if [ -d "$NEMOCLAW_DIR" ]; then
    export HOME=/home/zeus
    export OPENCLAW_HOME=/home/zeus/.openclaw-host
    export PATH="/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH"
    cd "$NEMOCLAW_DIR"
    ./scripts/start-services.sh >/dev/null 2>&1 || true
  fi
  sleep "$INTERVAL_SECONDS"
done
