#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_vm_ssh.sh"

REMOTE_TMP="${REMOTE_TMP:-/tmp/nemoclaw-vm-automation}"
REMOTE_INSTALL_DIR="${REMOTE_INSTALL_DIR:-/opt/nemoclaw-vm-automation}"
REMOTE_STUDIO_DIR="${REMOTE_STUDIO_DIR:-/home/zeus/content/.lightning_studio}"

ssh_retry "mkdir -p '$REMOTE_TMP'"
scp_retry \
  "$SCRIPT_DIR/../systemd/lightning-vm-keepalive.service" \
  "$SCRIPT_DIR/vm_keepalive_loop.sh" \
  "$SCRIPT_DIR/vm_snapshot_remote.py" \
  "$SCRIPT_DIR/../lightning_studio/on_start.sh" \
  "$SCRIPT_DIR/../lightning_studio/on_stop.sh" \
  "$TARGET:$REMOTE_TMP/"

ssh_retry "
  sudo mkdir -p '$REMOTE_INSTALL_DIR'
  mkdir -p '$REMOTE_STUDIO_DIR'
  sudo install -m 0755 '$REMOTE_TMP/vm_keepalive_loop.sh' '$REMOTE_INSTALL_DIR/vm_keepalive_loop.sh'
  sudo install -m 0755 '$REMOTE_TMP/vm_snapshot_remote.py' '$REMOTE_INSTALL_DIR/vm_snapshot_remote.py'
  sudo install -m 0644 '$REMOTE_TMP/lightning-vm-keepalive.service' /etc/systemd/system/lightning-vm-keepalive.service
  install -m 0755 '$REMOTE_TMP/on_start.sh' '$REMOTE_STUDIO_DIR/on_start.sh'
  install -m 0755 '$REMOTE_TMP/on_stop.sh' '$REMOTE_STUDIO_DIR/on_stop.sh'
  sudo systemctl daemon-reload
  sudo systemctl enable --now lightning-vm-keepalive.service
  sudo systemctl restart lightning-vm-keepalive.service
  bash '$REMOTE_STUDIO_DIR/on_start.sh' || true
  systemctl is-active lightning-vm-keepalive.service
"
