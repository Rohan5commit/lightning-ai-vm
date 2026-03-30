# Lightning Studio Keepalive Handoff

Date: `2026-03-29T10:44:40Z`

## Purpose

The free Lightning Studio backing the NemoClaw VM can drift asleep after about 10 minutes of inactivity. The first keepalive implementation only maintained a detached heartbeat session, which could still look healthy in GitHub Actions while the Studio later idled out.

Historical note:
- this document originally referred to `Rohan5commit/train-once-quant-platform`
- that was later corrected
- the current source of truth for VM automation is `Rohan5commit/lightning-ai-vm`

## Source Repo

- Repo: `Rohan5commit/lightning-ai-vm`

## What Changed

### GitHub Actions

- `lightning-progress-snapshot.yml`
  - now runs every 4 hours
  - acts as the slower archive/status checkpoint workflow
- `lightning-studio-keepalive.yml`
  - new workflow
  - now runs every 5 minutes instead of every 10
  - calls the Studio heal path
  - sends a fresh keepalive pulse command on every run so Lightning sees new activity, not just a stale long-running session
- all workflow helper actions were upgraded to the Node 24-capable releases:
  - `actions/checkout@v6`
  - `actions/setup-python@v6`
  - `actions/upload-artifact@v6`

### Runtime Code

- `scripts/lightning_studio_keepalive.py`
  - detached heartbeat worker that writes heartbeat JSON inside the Studio
  - now also supports one-shot pulse writes for the GitHub keepalive workflow
- `scripts/lightning_studio_run.py`
  - launches both the main workload session and the detached keepalive session
  - now also sends a one-shot keepalive pulse during startup
- `scripts/lightning_studio_snapshot.py`
  - heals the Studio, workload session, and keepalive session
  - now also sends a one-shot keepalive pulse on every scheduled run
- `src/lightning_studio_utils.py`
  - fixes the Studio config to use `disable_auto_shutdown=True`
  - adds keepalive pulse config, pulse session naming, and the resume hook command builder
  - the keepalive pulse is now inline, so it still works even if the Studio repo checkout has not refreshed to the newest helper script yet
- `configs/lightning_run.yaml`
  - enables keepalive and sets the interval to 240 seconds
  - enables the keepalive pulse
  - defines the default resume hook that restarts `/home/zeus/content/workspace/NemoClaw` if it exists

## Effective Behavior

1. Manual launch workflow starts the Studio workload and the detached keepalive session.
2. The detached keepalive session writes heartbeat state every 240 seconds inside the Studio workspace.
3. Every 5 minutes, GitHub Actions runs the keepalive workflow, wakes/heals the Studio if needed, and sends a fresh one-shot keepalive pulse command into the Studio.
4. The pulse also runs the resume hook so NemoClaw services are restarted automatically after a wake/resume.
5. Every 4 hours, GitHub Actions runs the snapshot workflow to archive/check the current state on a slower cadence.

## GitHub Workflows To Check

- `Launch Lightning Auto-Resume Studio`
- `Lightning Studio Keepalive`
- `Lightning Studio Snapshot`

## Notes

- This document is historical context only.
- The current executable VM automation now lives in this handoff repo.
