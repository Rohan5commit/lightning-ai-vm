# 2026-04-04 Exact NemoClaw Migration Status

## What was added

- `Migrate NemoClaw Stack`
  - bulk source-to-target copy of the current NemoClaw VM state
- `Apply NemoClaw Runtime`
  - materializes the exact Slack, NVIDIA, Supermemory, and Nemo runtime secrets onto the target Studio
  - smoke-tests the leader plus both assistants through the Lightning API remote-exec path

## Exact runtime parity

The repo now stores the runtime secrets needed to recreate the live stack in GitHub Secrets:

- `NEMOCLAW_SLACK_BOT_TOKEN`
- `NEMOCLAW_SLACK_APP_TOKEN`
- `NEMOCLAW_SLACK_VERIFICATION_TOKEN`
- `NEMOCLAW_NVIDIA_API_KEY_LEADER`
- `NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1`
- `NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2`
- `NEMOCLAW_SUPERMEMORY_API_KEY`
- `NEMOCLAW_NEMO_TOKEN`

This means the new target Studio no longer depends only on a live source VM for credentials.

## Current blocker

The new runtime workflow still fails before applying the copied stack because Lightning refuses to start the target Studio:

- workflow run: `23975334968`
- action: `blocked_insufficient_balance`
- target studio: `01knbqaeqfkr0j62rvzdxcp0ek`
- target project: `01knbq8tg7mmn55wf88erpv90b`

## Strong evidence for the real cause

Lightning project metadata shows:

- source project `01kjsr1b8s8zkck9x8t7hdsvgx`
  - `freeStorageBytes = 10737418240`
  - `currentStorageBytes = 21952890006`
- target project `01knbq8tg7mmn55wf88erpv90b`
  - `freeStorageBytes = 0`
  - `currentStorageBytes = 0`

The old source project contains a stale large cloudspace:

- cloudspace `parameter-golf`
- size `16126066493` bytes

The current live NemoClaw source cloudspace is:

- cloudspace `rude-teal-op1l`
- size `5863356899` bytes

Those two alone account for about `21.99 GB`, which matches the blocked source project storage.

## Operational implication

The new repo and workflows are ready for exact migration, but the Lightning account must have free Studio storage again before either:

- the old source Studio can be started for bulk copy, or
- the new target Studio can be started for exact secret materialization and smoke tests
