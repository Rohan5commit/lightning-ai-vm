#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/lightning_vm_remote.py" keepalive "$@" >/dev/null
python3 "$SCRIPT_DIR/lightning_vm_remote.py" exec "$@" \
  --session-name github-actions-pulse \
  --command "$(cat <<'SH'
python3 - <<'PY'
import json
import socket
from datetime import datetime, timezone
from pathlib import Path

keepalive_dir = Path('/teamspace/studios/this_studio/.lightning-checkpoints/nemoclaw-vm-keepalive')
keepalive_dir.mkdir(parents=True, exist_ok=True)
payload = {
    'kind': 'heartbeat',
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'host': socket.gethostname(),
    'source': 'github-actions-pulse',
}
(keepalive_dir / 'heartbeat.json').write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
(keepalive_dir / '.last-touch').touch()
PY
if ! systemctl is-active --quiet lightning-vm-keepalive.service; then
  sudo systemctl restart lightning-vm-keepalive.service || true
fi
if [ -d /home/zeus/content/workspace/NemoClaw ]; then
  export HOME=/home/zeus
  export OPENCLAW_HOME=/home/zeus/.openclaw-host
  export PATH="/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH"
  cd /home/zeus/content/workspace/NemoClaw
  ./scripts/start-services.sh >/dev/null 2>&1 || true
fi
python3 /opt/nemoclaw-vm-automation/vm_snapshot_remote.py
SH
)"
