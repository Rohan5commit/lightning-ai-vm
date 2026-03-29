# Lightning Studio Keepalive Handoff

Date: `2026-03-29T10:44:40Z`

## Purpose

The free Lightning Studio backing the NemoClaw VM can drift asleep after about 10 minutes of inactivity. The runtime repo was updated so GitHub Actions, not local-only state, keeps the Studio alive and relaunches it if needed.

## Runtime Repo

- Repo: `Rohan5commit/train-once-quant-platform`

## What Changed

### GitHub Actions

- `lightning-progress-snapshot.yml`
  - now runs every 4 hours
  - acts as the slower archive/status checkpoint workflow
- `lightning-studio-keepalive.yml`
  - new workflow
  - runs every 10 minutes
  - calls the Studio heal path so the free Studio does not stay asleep

### Runtime Code

- `scripts/lightning_studio_keepalive.py`
  - detached heartbeat worker that writes heartbeat JSON inside the Studio
- `scripts/lightning_studio_run.py`
  - launches both the main workload session and the detached keepalive session
- `scripts/lightning_studio_snapshot.py`
  - heals the Studio, workload session, and keepalive session
- `src/lightning_studio_utils.py`
  - adds keepalive config, heartbeat paths, and keepalive command builder
- `configs/lightning_run.yaml`
  - enables keepalive and sets the interval to 240 seconds

## Effective Behavior

1. Manual launch workflow starts the Studio workload and the detached keepalive session.
2. The keepalive session writes heartbeat state every 240 seconds inside the Studio workspace.
3. Every 10 minutes, GitHub Actions runs the keepalive workflow to ensure the Studio and detached sessions are still alive.
4. Every 4 hours, GitHub Actions runs the snapshot workflow to archive/check the current state on a slower cadence.

## GitHub Workflows To Check

- `Launch Lightning Auto-Resume Studio`
- `Lightning Studio Keepalive`
- `Lightning Studio Snapshot`

## Notes

- This handoff repo is documentation-only by design.
- The runtime repo is the only repo that should contain executable automation for the Lightning Studio keepalive path.
