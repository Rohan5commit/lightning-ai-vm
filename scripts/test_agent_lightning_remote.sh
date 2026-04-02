#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${AGENT_LIGHTNING_BIN_DIR:-/home/zeus/.local/bin}"
NODE_BIN_DIR="${NODE_BIN_DIR:-/system/conda/node/nvm/versions/node/v22.22.2/bin}"
export HOME=/home/zeus
export PATH="$BIN_DIR:$NODE_BIN_DIR:$PATH"

python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path

repo_dir = Path("/home/zeus/content/workspace/agent-lightning")
venv_python = Path("/home/zeus/.venvs/agent-lightning/bin/python")
agl = Path("/home/zeus/.local/bin/agl")

def run(cmd, env=None):
    proc = subprocess.run(cmd, text=True, capture_output=True, env=env)
    return {
        "cmd": cmd,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }

report = {
    "repo_exists": repo_dir.exists(),
    "repo_head": run(["git", "-C", str(repo_dir), "rev-parse", "HEAD"]),
    "import_check": run([str(venv_python), "-c", "import agentlightning; print(agentlightning.__file__)"]),
    "agl_help": run(["timeout", "60", str(agl), "--help"]),
    "agl_store_help": run(["timeout", "60", str(agl), "store", "--help"]),
    "agents": {},
}

for label, openclaw_home in {
    "leader": "/home/zeus/.openclaw-host",
    "assistant1": "/home/zeus/.openclaw-assistant-host",
    "assistant2": "/home/zeus/.openclaw-assistant2-host",
}.items():
    env = dict(os.environ)
    env["OPENCLAW_HOME"] = openclaw_home
    env["HOME"] = "/home/zeus"
    skills = run(["timeout", "60", "openclaw", "skills", "list"], env=env)
    skill_file = Path(openclaw_home) / ".openclaw" / "extra-skills-curated" / "agent-lightning" / "SKILL.md"
    report["agents"][label] = {
        "skill_file_exists": skill_file.exists(),
        "skills_list_contains_agent_lightning": "agent-lightning" in skills["stdout"],
        "skills_list": skills,
    }

print(json.dumps(report, indent=2))
PY
