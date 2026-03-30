#!/usr/bin/env bash
set -euo pipefail

TARGET="${LIGHTNING_VM_TARGET:?LIGHTNING_VM_TARGET is required}"
KEY_FILE="${LIGHTNING_VM_SSH_KEY_FILE:?LIGHTNING_VM_SSH_KEY_FILE is required}"
KEY_FILE="${KEY_FILE/#\~/$HOME}"
KNOWN_HOSTS_FILE="${LIGHTNING_VM_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE/#\~/$HOME}"
SSH_RETRIES="${LIGHTNING_VM_SSH_RETRIES:-12}"
SSH_RETRY_DELAY="${LIGHTNING_VM_SSH_RETRY_DELAY:-15}"

mkdir -p "$HOME/.ssh" "$(dirname "$KNOWN_HOSTS_FILE")"
chmod 700 "$HOME/.ssh"
touch "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

if ! ssh-keygen -F ssh.lightning.ai -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
  ssh-keyscan -H ssh.lightning.ai >>"$KNOWN_HOSTS_FILE" 2>/dev/null || true
fi

SSH_OPTS=(
  -i "$KEY_FILE"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE"
  -o UpdateHostKeys=no
  -o ConnectTimeout=20
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
)

retry_run() {
  local label="$1"
  shift
  local attempt=1
  local max_attempts="$SSH_RETRIES"
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "$label failed after $attempt attempts" >&2
      return 1
    fi
    echo "$label failed on attempt $attempt/$max_attempts; retrying in ${SSH_RETRY_DELAY}s" >&2
    sleep "$SSH_RETRY_DELAY"
    attempt=$((attempt + 1))
  done
}

ssh_retry() {
  retry_run "ssh" ssh "${SSH_OPTS[@]}" "$TARGET" "$@"
}

scp_retry() {
  retry_run "scp" scp "${SSH_OPTS[@]}" "$@"
}
