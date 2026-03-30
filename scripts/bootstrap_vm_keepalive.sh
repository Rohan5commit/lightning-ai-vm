#!/usr/bin/env bash
set -euo pipefail

TARGET="${LIGHTNING_VM_TARGET:?LIGHTNING_VM_TARGET is required}"
KEY_FILE="${LIGHTNING_VM_SSH_KEY_FILE:?LIGHTNING_VM_SSH_KEY_FILE is required}"
REMOTE_TMP="${REMOTE_TMP:-/tmp/nemoclaw-vm-automation}"
REMOTE_INSTALL_DIR="${REMOTE_INSTALL_DIR:-/opt/nemoclaw-vm-automation}"

SSH_OPTS=(
  -i "$KEY_FILE"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o UpdateHostKeys=no
)

ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p '$REMOTE_TMP'"
scp "${SSH_OPTS[@]}" \
  systemd/lightning-vm-keepalive.service \
  scripts/vm_keepalive_loop.sh \
  scripts/vm_snapshot_remote.py \
  "$TARGET:$REMOTE_TMP/"

ssh "${SSH_OPTS[@]}" "$TARGET" "
  sudo mkdir -p '$REMOTE_INSTALL_DIR'
  sudo install -m 0755 '$REMOTE_TMP/vm_keepalive_loop.sh' '$REMOTE_INSTALL_DIR/vm_keepalive_loop.sh'
  sudo install -m 0755 '$REMOTE_TMP/vm_snapshot_remote.py' '$REMOTE_INSTALL_DIR/vm_snapshot_remote.py'
  sudo install -m 0644 '$REMOTE_TMP/lightning-vm-keepalive.service' /etc/systemd/system/lightning-vm-keepalive.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now lightning-vm-keepalive.service
  sudo systemctl restart lightning-vm-keepalive.service
  systemctl is-active lightning-vm-keepalive.service
"
