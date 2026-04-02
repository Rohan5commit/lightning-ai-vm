#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${AGENT_LIGHTNING_REPO_DIR:-/home/zeus/content/workspace/agent-lightning}"
VENV_DIR="${AGENT_LIGHTNING_VENV_DIR:-/home/zeus/.venvs/agent-lightning}"
BIN_DIR="${AGENT_LIGHTNING_BIN_DIR:-/home/zeus/.local/bin}"
WORKSPACE_DIR="$(dirname "$REPO_DIR")"
NODE_BIN_DIR="${NODE_BIN_DIR:-/system/conda/node/nvm/versions/node/v22.22.2/bin}"

mkdir -p "$WORKSPACE_DIR" "$BIN_DIR" "$(dirname "$VENV_DIR")"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" fetch --depth=1 origin main
  git -C "$REPO_DIR" reset --hard origin/main
else
  rm -rf "$REPO_DIR"
  git clone --depth=1 https://github.com/microsoft/agent-lightning "$REPO_DIR"
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
"$VENV_DIR/bin/pip" install -e "$REPO_DIR"

cat > "$BIN_DIR/agl" <<'SH'
#!/usr/bin/env bash
exec /home/zeus/.venvs/agent-lightning/bin/agl "$@"
SH
chmod +x "$BIN_DIR/agl"

cat > "$BIN_DIR/agent-lightning-python" <<'SH'
#!/usr/bin/env bash
exec /home/zeus/.venvs/agent-lightning/bin/python "$@"
SH
chmod +x "$BIN_DIR/agent-lightning-python"

create_skill() {
  local openclaw_home="$1"
  local skill_dir="$openclaw_home/.openclaw/extra-skills-curated/agent-lightning"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'MD'
# Agent Lightning

Use this skill when you need to inspect, instrument, or train agents with Microsoft Agent Lightning on this VM.

## Available paths

- Repo: `/home/zeus/content/workspace/agent-lightning`
- Python env: `/home/zeus/.venvs/agent-lightning`
- CLI wrapper: `/home/zeus/.local/bin/agl`
- Python wrapper: `/home/zeus/.local/bin/agent-lightning-python`

## Safe usage

1. Inspect the CLI first with `agl --help` or `agl store --help`.
2. Prefer read-only inspection or local smoke tests unless the user explicitly asks for training jobs.
3. Run Python examples with `/home/zeus/.local/bin/agent-lightning-python`.
4. Use the shared VM install instead of creating duplicate per-agent copies.

## Quick smoke tests

```bash
agl store --help
agent-lightning-python -c "import agentlightning; print(agentlightning.__file__)"
```

## Notes

- The shared install is available to the leader and both junior NemoClaws.
- The upstream repository is `/home/zeus/content/workspace/agent-lightning`.
MD
}

for openclaw_home in \
  /home/zeus/.openclaw-host \
  /home/zeus/.openclaw-assistant-host \
  /home/zeus/.openclaw-assistant2-host
do
  create_skill "$openclaw_home"
done

for sessions_file in \
  /home/zeus/.openclaw-host/.openclaw/agents/main/sessions/sessions.json \
  /home/zeus/.openclaw-assistant-host/.openclaw/agents/main/sessions/sessions.json \
  /home/zeus/.openclaw-assistant2-host/.openclaw/agents/main/sessions/sessions.json
do
  [ -f "$sessions_file" ] || continue
  python3 - "$sessions_file" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())

def scrub(node):
    if isinstance(node, dict):
        if "skillsSnapshot" in node:
            node.pop("skillsSnapshot", None)
        for value in node.values():
            scrub(value)
    elif isinstance(node, list):
        for item in node:
            scrub(item)

scrub(data)
path.write_text(json.dumps(data, indent=2) + "\n")
PY
done

export HOME=/home/zeus
export PATH="$BIN_DIR:$NODE_BIN_DIR:$PATH"
