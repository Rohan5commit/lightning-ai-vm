#!/usr/bin/env bash
set -euo pipefail

TARGET="${LIGHTNING_VM_TARGET:?LIGHTNING_VM_TARGET is required}"
KEY_FILE="${LIGHTNING_VM_SSH_KEY_FILE:?LIGHTNING_VM_SSH_KEY_FILE is required}"

SSH_OPTS=(
  -i "$KEY_FILE"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o UpdateHostKeys=no
)

ssh "${SSH_OPTS[@]}" "$TARGET" "python3 /opt/nemoclaw-vm-automation/vm_snapshot_remote.py"
