#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_vm_ssh.sh"

ssh_retry "python3 - <<'PY'
import json
import subprocess

def run(cmd, env=None):
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    return {
        'returncode': proc.returncode,
        'stdout': (proc.stdout or '').strip(),
        'stderr': (proc.stderr or '').strip(),
    }

base_env = {
    'HOME': '/home/zeus',
    'OPENCLAW_HOME': '/home/zeus/.openclaw-host',
    'PATH': '/system/conda/node/nvm/versions/node/v22.22.2/bin:' + subprocess.run(['bash', '-lc', 'printf %s \"$PATH\"'], capture_output=True, text=True).stdout.strip(),
}
assistant1_env = {
    'HOME': '/home/zeus/.openclaw-assistant-host',
    'OPENCLAW_HOME': '/home/zeus/.openclaw-assistant-host',
    'PATH': base_env['PATH'],
}
assistant2_env = {
    'HOME': '/home/zeus/.openclaw-assistant2-host',
    'OPENCLAW_HOME': '/home/zeus/.openclaw-assistant2-host',
    'PATH': base_env['PATH'],
}

skills_output = run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-host OPENCLAW_HOME=/home/zeus/.openclaw-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw skills list'], env=base_env)
skills_text = (skills_output['stdout'] + '\n' + skills_output['stderr']).lower()

payload = {
    'hostname': run(['hostname'])['stdout'],
    'leader': {
        'health': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-host OPENCLAW_HOME=/home/zeus/.openclaw-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw health'], env=base_env),
        'browser_status': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-host OPENCLAW_HOME=/home/zeus/.openclaw-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw browser status'], env=base_env),
        'slack_bridge_health': run(['curl', '-fsS', 'http://127.0.0.1:38080/healthz']),
        'supermemory_status': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-host OPENCLAW_HOME=/home/zeus/.openclaw-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw supermemory status'], env=base_env),
        'health_ok': 'slack: ok' in run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-host OPENCLAW_HOME=/home/zeus/.openclaw-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw health'], env=base_env)['stdout'].lower(),
        'slack_bridge_ok': run(['curl', '-fsS', 'http://127.0.0.1:38080/healthz'])['returncode'] == 0,
        'skills': {
            'agent-lightning': 'agent-lightning' in skills_text,
            'nemo-video': 'nemo-video' in skills_text,
            'scrapling': 'scrapling' in skills_text,
            'clawhub': 'clawhub' in skills_text,
            'nerve-kanban': 'nerve-kanban' in skills_text,
        },
    },
    'assistant1': {
        'health': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-assistant-host OPENCLAW_HOME=/home/zeus/.openclaw-assistant-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw health'], env=assistant1_env),
        'browser_status': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-assistant-host OPENCLAW_HOME=/home/zeus/.openclaw-assistant-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw browser status'], env=assistant1_env),
        'browser_helper_health': run(['curl', '-fsS', 'http://127.0.0.1:28890/healthz']),
        'browser_helper_ok': run(['curl', '-fsS', 'http://127.0.0.1:28890/healthz'])['returncode'] == 0,
    },
    'assistant2': {
        'health': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-assistant2-host OPENCLAW_HOME=/home/zeus/.openclaw-assistant2-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw health'], env=assistant2_env),
        'browser_status': run(['bash', '-lc', 'export HOME=/home/zeus/.openclaw-assistant2-host OPENCLAW_HOME=/home/zeus/.openclaw-assistant2-host PATH=\"/system/conda/node/nvm/versions/node/v22.22.2/bin:$PATH\"; openclaw browser status'], env=assistant2_env),
        'browser_helper_health': run(['curl', '-fsS', 'http://127.0.0.1:38890/healthz']),
        'browser_helper_ok': run(['curl', '-fsS', 'http://127.0.0.1:38890/healthz'])['returncode'] == 0,
    },
    'lightpanda': {
        'helper_health': run(['curl', '-fsS', 'http://127.0.0.1:18891/healthz']),
        'helper_ok': run(['curl', '-fsS', 'http://127.0.0.1:18891/healthz'])['returncode'] == 0,
    },
}

print(json.dumps(payload, indent=2))
PY"
