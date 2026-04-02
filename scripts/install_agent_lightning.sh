#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_vm_ssh.sh"

REMOTE_TMP="${REMOTE_TMP:-/tmp/nemoclaw-vm-automation}"

ssh_retry "mkdir -p '$REMOTE_TMP'"
scp_retry "$SCRIPT_DIR/install_agent_lightning_remote.sh" "$TARGET:$REMOTE_TMP/install_agent_lightning_remote.sh"
ssh_retry "
  chmod +x '$REMOTE_TMP/install_agent_lightning_remote.sh'
  bash '$REMOTE_TMP/install_agent_lightning_remote.sh'
"
