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
  "$SCRIPT_DIR/../systemd/billing-monitor.service" \
  "$SCRIPT_DIR/../systemd/billing-monitor.timer" \
  "$SCRIPT_DIR/../systemd/billing-board.service" \
  "$SCRIPT_DIR/vm_keepalive_loop.sh" \
  "$SCRIPT_DIR/vm_snapshot_remote.py" \
  "$SCRIPT_DIR/billing_monitor.py" \
  "$SCRIPT_DIR/../lightning_studio/on_start.sh" \
  "$SCRIPT_DIR/../lightning_studio/on_stop.sh" \
  "$TARGET:$REMOTE_TMP/"

if [ -n "${OCI_PRIVATE_KEY:-}" ]; then
  LOCAL_BILLING_TMP="$(mktemp -d)"
  trap 'rm -rf "$LOCAL_BILLING_TMP"' EXIT
  cat >"$LOCAL_BILLING_TMP/nemoclaw-billing-monitor.env" <<EOF
BILLING_ALERT_THRESHOLD=${BILLING_ALERT_THRESHOLD:-0.50}
BILLING_SMTP_HOST=${BILLING_SMTP_HOST:-smtp.gmail.com}
BILLING_SMTP_PORT=${BILLING_SMTP_PORT:-465}
BILLING_SMTP_USERNAME=${BILLING_SMTP_USERNAME:-}
BILLING_SMTP_PASSWORD=${BILLING_SMTP_PASSWORD:-}
BILLING_ALERT_EMAIL_TO=${BILLING_ALERT_EMAIL_TO:-}
OCI_CONFIG_FILE=/etc/nemoclaw-billing-monitor/oci_config
OCI_CONFIG_PROFILE=DEFAULT
ALIBABA_ACCESS_KEY_ID=${ALIBABA_ACCESS_KEY_ID:-}
ALIBABA_ACCESS_KEY_SECRET=${ALIBABA_ACCESS_KEY_SECRET:-}
ALIBABA_BILLING_ENDPOINT=${ALIBABA_BILLING_ENDPOINT:-business.aliyuncs.com}
BILLING_DB_PATH=/var/lib/nemoclaw-billing/billing.sqlite3
BILLING_STATE_DIR=/var/lib/nemoclaw-billing
BILLING_BOARD_DIR=/var/lib/nemoclaw-billing/www
EOF
  cat >"$LOCAL_BILLING_TMP/oci_config" <<EOF
[DEFAULT]
user=${OCI_USER:-}
fingerprint=${OCI_FINGERPRINT:-}
tenancy=${OCI_TENANCY:-}
region=${OCI_REGION:-}
key_file=/etc/nemoclaw-billing-monitor/oci_api_key.pem
EOF
  printf '%s\n' "$OCI_PRIVATE_KEY" >"$LOCAL_BILLING_TMP/oci_api_key.pem"
  chmod 600 "$LOCAL_BILLING_TMP/oci_api_key.pem" "$LOCAL_BILLING_TMP/nemoclaw-billing-monitor.env" "$LOCAL_BILLING_TMP/oci_config"
  scp_retry \
    "$LOCAL_BILLING_TMP/nemoclaw-billing-monitor.env" \
    "$LOCAL_BILLING_TMP/oci_config" \
    "$LOCAL_BILLING_TMP/oci_api_key.pem" \
    "$TARGET:$REMOTE_TMP/"
fi

ssh_retry "
  sudo mkdir -p '$REMOTE_INSTALL_DIR'
  sudo mkdir -p /etc/nemoclaw-billing-monitor
  sudo mkdir -p /var/lib/nemoclaw-billing/www
  mkdir -p '$REMOTE_STUDIO_DIR'
  sudo install -m 0755 '$REMOTE_TMP/vm_keepalive_loop.sh' '$REMOTE_INSTALL_DIR/vm_keepalive_loop.sh'
  sudo install -m 0755 '$REMOTE_TMP/vm_snapshot_remote.py' '$REMOTE_INSTALL_DIR/vm_snapshot_remote.py'
  sudo install -m 0755 '$REMOTE_TMP/billing_monitor.py' '$REMOTE_INSTALL_DIR/billing_monitor.py'
  sudo install -m 0644 '$REMOTE_TMP/lightning-vm-keepalive.service' /etc/systemd/system/lightning-vm-keepalive.service
  sudo install -m 0644 '$REMOTE_TMP/billing-monitor.service' /etc/systemd/system/billing-monitor.service
  sudo install -m 0644 '$REMOTE_TMP/billing-monitor.timer' /etc/systemd/system/billing-monitor.timer
  sudo install -m 0644 '$REMOTE_TMP/billing-board.service' /etc/systemd/system/billing-board.service
  install -m 0755 '$REMOTE_TMP/on_start.sh' '$REMOTE_STUDIO_DIR/on_start.sh'
  install -m 0755 '$REMOTE_TMP/on_stop.sh' '$REMOTE_STUDIO_DIR/on_stop.sh'
  if [ -f '$REMOTE_TMP/nemoclaw-billing-monitor.env' ]; then
    sudo install -m 0600 '$REMOTE_TMP/nemoclaw-billing-monitor.env' /etc/nemoclaw-billing-monitor.env
    sudo install -m 0600 '$REMOTE_TMP/oci_config' /etc/nemoclaw-billing-monitor/oci_config
    sudo install -m 0600 '$REMOTE_TMP/oci_api_key.pem' /etc/nemoclaw-billing-monitor/oci_api_key.pem
    sudo mkdir -p '$REMOTE_INSTALL_DIR/vendor'
    sudo python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    sudo python3 -m pip install --upgrade pip >/dev/null 2>&1 || true
    sudo python3 -m pip install --target '$REMOTE_INSTALL_DIR/vendor' oci >/dev/null
  fi
  sudo systemctl daemon-reload
  sudo systemctl enable --now lightning-vm-keepalive.service
  if [ -f /etc/nemoclaw-billing-monitor.env ]; then
    sudo systemctl enable --now billing-board.service
    sudo systemctl enable --now billing-monitor.timer
    sudo systemctl restart billing-board.service
    sudo systemctl start billing-monitor.service || true
  fi
  sudo systemctl restart lightning-vm-keepalive.service
  bash '$REMOTE_STUDIO_DIR/on_start.sh' || true
  systemctl is-active lightning-vm-keepalive.service
"
