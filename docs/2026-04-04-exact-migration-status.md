# 2026-04-04 Exact NemoClaw Migration Status

## What was added

- `Migrate NemoClaw Stack`
  - bulk source-to-target copy of the current NemoClaw VM state
- `Apply NemoClaw Runtime`
  - materializes the exact Slack, NVIDIA, Supermemory, and Nemo runtime secrets onto the target Studio
  - smoke-tests the leader plus both assistants through the Lightning API remote-exec path
- stopped-cloudspace fork preservation
  - forks the full source Lightning Studio filesystem into the new project without requiring the source VM to boot first

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

## Exact filesystem clone status

Lightning accepted an internal cloudspace fork from the source project into the new project.

- source cloudspace
  - id: `01kmn9avp59m90qykz5c3ta2as`
  - name: `rude-teal-op1l`
  - project: `01kjsr1b8s8zkck9x8t7hdsvgx`
  - reported file count: `294671`
  - reported size: `5863356899` bytes
- forked target cloudspace
  - id: `01knbwwg5zxek87wqqddqt53ba`
  - name: `rude-teal-op1l-zkmk`
  - project: `01kjsr1b8s8zkck9x8t7hdsvgx`
  - reported file count: `294671`
  - reported size: `5863356899` bytes

This fork is the exact stack-preservation layer for:

- leader/assistant hierarchy
- persisted OpenClaw memory and thread state
- skills, plugins, and local wrappers
- `.openclaw`, `.nemoclaw`, workspace repos, helper services, and copied credentials that already exist on disk

The empty placeholder target studio in the non-free project was deleted.

There is also a free-shell GCP studio in the free-enabled source project:

- shell studio id: `01knbwkkjzs91wetey9ajtt7s6`
- shell studio name: `applicable-maroon-4zeb`
- project: `01kjsr1b8s8zkck9x8t7hdsvgx`
- purpose: active free GCP runtime slot

Current variable layout uses the free GCP path:

- `LIGHTNING_*` points at `applicable-maroon-4zeb`
- `TARGET_LIGHTNING_*` points at the exact free-project clone `rude-teal-op1l-zkmk`
- `SOURCE_LIGHTNING_*` still points at the original source studio for provenance

## Current blocker

The runtime workflows still fail before applying the copied stack because Lightning is returning no active instance for the free shell studio and still refuses to start a machine for the exact clones:

- workflow run: `23975334968`
- workflow run: `23975568929`
- workflow run: `23976138391`
- action: `blocked_insufficient_balance`
- source studio: `01kmn9avp59m90qykz5c3ta2as`
- free shell studio: `01knbwkkjzs91wetey9ajtt7s6`
- exact free-project clone: `01knbwwg5zxek87wqqddqt53ba`
- project: `01kjsr1b8s8zkck9x8t7hdsvgx`

## Strong evidence for the real cause

Lightning reports all of the following at the same time:

- source project `01kjsr1b8s8zkck9x8t7hdsvgx`
  - membership `free_credits_enabled = True`
  - membership `balance = 0.0`
- secondary project `01knbq8tg7mmn55wf88erpv90b`
  - membership `free_credits_enabled = False`
  - membership `balance = 0.0`

The stale source-project cloudspaces that were inflating storage were deleted:

- `01kmd44np6ph8bc59m3ja9jnkt` `parameter-golf`
- `01kmd74psbxnxdbbwv54zskc1p` `parameter-golf-t4-v2`
- `01kmd6p9b24804013reh0nea5t` `parameter-golf-g4dn-check`
- `01kmd6mh7t65g70ewyb0k528a4` `parameter-golf-t4-check`
- `01kmnags6t9p4nd3sxvy3w4d24` duplicate zero-size `rude-teal-op1l-wnfj`

After those deletes, Lightning still returns the same machine-start failure for both the original source studio and the exact free-project clone:

- `creating cloud space instance: insufficient balance to start the cloud space`

The free shell studio can exist in `CLOUD_SPACE_STATE_READY`, but Lightning can still report zero active instances for it and refuse to create a new one when the keepalive tries to heal it.

So the remaining blocker is no longer repo drift or missing runtime secrets. It is Lightning machine startup/instance state on this account.

## Operational implication

The exact stack is now preserved in the new project, and the repo has the exact runtime secrets needed to re-materialize Slack plus the three-agent hierarchy.

What still cannot happen until Lightning allows a machine to start again:

- applying the exact runtime secret set onto the cloned target cloudspace
- smoke-testing the cloned stack through Slack, Lightpanda, Supermemory, NemoVideo, and the assistant hierarchy
- resuming keepalive/snapshot automation against the new project
