#!/usr/bin/env bash
set -euo pipefail

SOURCE_TARGET="${SOURCE_LIGHTNING_VM_TARGET:?SOURCE_LIGHTNING_VM_TARGET is required}"
TARGET_TARGET="${LIGHTNING_VM_TARGET:?LIGHTNING_VM_TARGET is required}"
KEY_FILE="${LIGHTNING_VM_SSH_KEY_FILE:?LIGHTNING_VM_SSH_KEY_FILE is required}"
KEY_FILE="${KEY_FILE/#\~/$HOME}"
KNOWN_HOSTS_FILE="${LIGHTNING_VM_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_FILE/#\~/$HOME}"

mkdir -p "$HOME/.ssh" "$(dirname "$KNOWN_HOSTS_FILE")"
chmod 700 "$HOME/.ssh"
touch "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

if ! ssh-keygen -F ssh.lightning.ai -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
  ssh-keyscan -H ssh.lightning.ai >>"$KNOWN_HOSTS_FILE" 2>/dev/null || true
fi

SSH_COMMON_OPTS=(
  -i "$KEY_FILE"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE"
  -o UpdateHostKeys=no
  -o ConnectTimeout=30
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=4
)

SOURCE_TAR_CMD="$(cat <<'SH'
set -euo pipefail
paths=(
  home/zeus/.nemoclaw
  home/zeus/.openclaw-host
  home/zeus/.openclaw-assistant-host
  home/zeus/.openclaw-assistant2-host
  home/zeus/.local
  home/zeus/.venvs/agent-lightning
  home/zeus/content/.lightning_studio
  home/zeus/content/workspace/NemoClaw
  home/zeus/content/workspace/NemoClaw-assistant
  home/zeus/content/workspace/NemoClaw-assistant2
  home/zeus/content/workspace/Scrapling
  home/zeus/content/workspace/Scrapling-assistant
  home/zeus/content/workspace/agent-lightning
  home/zeus/content/workspace/lightpanda-browser
  home/zeus/content/workspace/openclaw-supermemory
  home/zeus/content/workspace/supermemory
  home/zeus/nerve
  home/zeus/nerve-assistant
  opt/nemoclaw-vm-automation
  etc/systemd/system/lightpanda.service
  etc/systemd/system/lightpanda-helper.service
  etc/systemd/system/nerve.service
  etc/systemd/system/nemoclaw-assistant.service
  etc/systemd/system/nemoclaw-assistant2.service
)
existing=()
for path in "${paths[@]}"; do
  if [ -e "/$path" ]; then
    existing+=("$path")
  fi
done
if [ "${#existing[@]}" -eq 0 ]; then
  echo "No NemoClaw migration paths found on source studio." >&2
  exit 1
fi
sudo tar czf - -C / "${existing[@]}"
SH
)"

TARGET_EXTRACT_CMD="$(cat <<'SH'
set -euo pipefail
sudo tar xzf - -C /
sudo systemctl daemon-reload
for svc in lightpanda.service lightpanda-helper.service nerve.service nemoclaw-assistant.service nemoclaw-assistant2.service lightning-vm-keepalive.service; do
  sudo systemctl enable --now "$svc" >/dev/null 2>&1 || true
done
if [ -x /home/zeus/content/.lightning_studio/on_start.sh ]; then
  bash /home/zeus/content/.lightning_studio/on_start.sh >/dev/null 2>&1 || true
fi
if [ -x /home/zeus/content/workspace/NemoClaw/scripts/start-services.sh ]; then
  export HOME=/home/zeus
  export OPENCLAW_HOME=/home/zeus/.openclaw-host
  export PATH="/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH"
  cd /home/zeus/content/workspace/NemoClaw
  ./scripts/start-services.sh >/dev/null 2>&1 || true
fi
echo "migration_extract_complete"
SH
)"

printf 'source=%s\n' "$SOURCE_TARGET"
printf 'target=%s\n' "$TARGET_TARGET"

ssh "${SSH_COMMON_OPTS[@]}" "$SOURCE_TARGET" "bash -lc $(printf '%q' "$SOURCE_TAR_CMD")" \
  | ssh "${SSH_COMMON_OPTS[@]}" "$TARGET_TARGET" "bash -lc $(printf '%q' "$TARGET_EXTRACT_CMD")"
