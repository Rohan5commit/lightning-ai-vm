#!/bin/bash
set -euo pipefail

LOG_DIR="$HOME/.lightning_studio/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/nemoclaw-vm-on_start.log"

{
  echo "[$(date -Is)] on_start begin"
  if sudo systemctl list-unit-files lightning-vm-keepalive.service >/dev/null 2>&1; then
    sudo systemctl daemon-reload || true
    sudo systemctl enable --now lightning-vm-keepalive.service || true
    sudo systemctl restart lightning-vm-keepalive.service || true
    systemctl is-active lightning-vm-keepalive.service || true
  fi

  if [ -d /home/zeus/content/workspace/NemoClaw ]; then
    export HOME=/home/zeus
    export OPENCLAW_HOME=/home/zeus/.openclaw-host
    export PATH="/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH"
    cd /home/zeus/content/workspace/NemoClaw
    ./scripts/start-services.sh >/dev/null 2>&1 || true
  fi
  echo "[$(date -Is)] on_start end"
} >>"$LOG_FILE" 2>&1
