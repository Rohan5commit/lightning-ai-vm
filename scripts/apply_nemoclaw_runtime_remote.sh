#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

required_envs=(
  NEMOCLAW_SLACK_BOT_TOKEN
  NEMOCLAW_SLACK_APP_TOKEN
  NEMOCLAW_SLACK_VERIFICATION_TOKEN
  NEMOCLAW_NVIDIA_API_KEY_LEADER
  NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1
  NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2
  NEMOCLAW_SUPERMEMORY_API_KEY
  NEMOCLAW_NEMO_TOKEN
)

for name in "${required_envs[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
done

quote() {
  printf "%q" "$1"
}

REMOTE_CMD="$(cat <<EOF
set -euo pipefail
export NEMOCLAW_SLACK_BOT_TOKEN=$(quote "${NEMOCLAW_SLACK_BOT_TOKEN}")
export NEMOCLAW_SLACK_APP_TOKEN=$(quote "${NEMOCLAW_SLACK_APP_TOKEN}")
export NEMOCLAW_SLACK_VERIFICATION_TOKEN=$(quote "${NEMOCLAW_SLACK_VERIFICATION_TOKEN}")
export NEMOCLAW_NVIDIA_API_KEY_LEADER=$(quote "${NEMOCLAW_NVIDIA_API_KEY_LEADER}")
export NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1=$(quote "${NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1}")
export NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2=$(quote "${NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2}")
export NEMOCLAW_SUPERMEMORY_API_KEY=$(quote "${NEMOCLAW_SUPERMEMORY_API_KEY}")
export NEMOCLAW_NEMO_TOKEN=$(quote "${NEMOCLAW_NEMO_TOKEN}")
python3 - <<'PY'
import json
import os
from pathlib import Path

leader_slack = {
    "SLACK_BOT_TOKEN": os.environ["NEMOCLAW_SLACK_BOT_TOKEN"],
    "SLACK_APP_TOKEN": os.environ["NEMOCLAW_SLACK_APP_TOKEN"],
    "SLACK_VERIFICATION_TOKEN": os.environ["NEMOCLAW_SLACK_VERIFICATION_TOKEN"],
}
supermemory_key = os.environ["NEMOCLAW_SUPERMEMORY_API_KEY"]
nemo_token = os.environ["NEMOCLAW_NEMO_TOKEN"]
role_nvidia = {
    "leader": os.environ["NEMOCLAW_NVIDIA_API_KEY_LEADER"],
    "assistant1": os.environ["NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1"],
    "assistant2": os.environ["NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2"],
}

role_roots = {
    "leader": Path("/home/zeus/.openclaw-host"),
    "assistant1": Path("/home/zeus/.openclaw-assistant-host"),
    "assistant2": Path("/home/zeus/.openclaw-assistant2-host"),
}

global_paths = [
    Path("/home/zeus/.nemoclaw/credentials.json"),
]

for path in global_paths:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except Exception:
            data = {}
    data.update(leader_slack)
    data["NEMO_TOKEN"] = nemo_token
    data["NVIDIA_API_KEY"] = role_nvidia["leader"]
    data["SUPERMEMORY_API_KEY"] = supermemory_key
    path.write_text(json.dumps(data, indent=2) + "\n")


def patch_strings(node, *, nvidia_key, include_slack):
    if isinstance(node, dict):
        for key, value in list(node.items()):
            lower_key = str(key).lower()
            if isinstance(value, str):
                if lower_key in {"nvidia_api_key", "nim_api_key"} or value.startswith("nvapi-"):
                    node[key] = nvidia_key
                elif lower_key in {"supermemory_api_key", "supermemoryapikey"} or value.startswith("sm_"):
                    node[key] = supermemory_key
                elif lower_key in {"nemo_token"}:
                    node[key] = nemo_token
                elif include_slack and lower_key in {"slack_bot_token", "bot_token"}:
                    node[key] = leader_slack["SLACK_BOT_TOKEN"]
                elif include_slack and lower_key in {"slack_app_token", "app_token"}:
                    node[key] = leader_slack["SLACK_APP_TOKEN"]
                elif include_slack and lower_key in {"slack_verification_token", "verification_token"}:
                    node[key] = leader_slack["SLACK_VERIFICATION_TOKEN"]
            else:
                patch_strings(value, nvidia_key=nvidia_key, include_slack=include_slack)
        if "supermemory" in {str(k).lower() for k in node.keys()}:
            for candidate in ("apiKey", "api_key", "token"):
                if isinstance(node.get(candidate), str):
                    node[candidate] = supermemory_key
        if "nemo" in {str(k).lower() for k in node.keys()}:
            for candidate in ("token", "nemoToken", "nemo_token"):
                if isinstance(node.get(candidate), str):
                    node[candidate] = nemo_token
    elif isinstance(node, list):
        for item in node:
            patch_strings(item, nvidia_key=nvidia_key, include_slack=include_slack)


for role, root in role_roots.items():
    cred_path = root / ".nemoclaw" / "credentials.json"
    cred_path.parent.mkdir(parents=True, exist_ok=True)
    data = {}
    if cred_path.exists():
        try:
            data = json.loads(cred_path.read_text())
        except Exception:
            data = {}
    data["NVIDIA_API_KEY"] = role_nvidia[role]
    data["NEMO_TOKEN"] = nemo_token
    data["SUPERMEMORY_API_KEY"] = supermemory_key
    if role == "leader":
        data.update(leader_slack)
    else:
        for slack_key in list(leader_slack):
            data.pop(slack_key, None)
    cred_path.write_text(json.dumps(data, indent=2) + "\n")

    openclaw_json = root / ".openclaw" / "openclaw.json"
    if openclaw_json.exists():
        try:
            config = json.loads(openclaw_json.read_text())
        except Exception:
            config = None
        if config is not None:
            patch_strings(config, nvidia_key=role_nvidia[role], include_slack=(role == "leader"))
            openclaw_json.write_text(json.dumps(config, indent=2) + "\n")

runtime_dir = Path("/home/zeus/.openclaw-host/.openclaw/files/services/default/runtime")
runtime_dir.mkdir(parents=True, exist_ok=True)
(runtime_dir / "nemoclaw-runtime.json").write_text(
    json.dumps(
        {
            "roles": {
                "leader": {"has_slack": True, "nvidia_key_present": True},
                "assistant1": {"has_slack": False, "nvidia_key_present": True},
                "assistant2": {"has_slack": False, "nvidia_key_present": True},
            },
            "supermemory_present": True,
            "nemo_token_present": True,
        },
        indent=2,
    )
    + "\n"
)

print(json.dumps({"ok": True, "applied_roles": sorted(role_roots.keys())}, indent=2))
PY
EOF
)"

python3 "$SCRIPT_DIR/lightning_vm_remote.py" exec \
  --session-name nemoclaw-runtime-apply \
  --command "$REMOTE_CMD"
