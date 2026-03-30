#!/bin/bash
set -euo pipefail

LOG_DIR="$HOME/.lightning_studio/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/nemoclaw-vm-on_stop.log"

{
  echo "[$(date -Is)] on_stop invoked"
} >>"$LOG_FILE" 2>&1
