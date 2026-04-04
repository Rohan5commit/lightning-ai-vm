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
  - id: `01knbvzmj0ttzzpdndcbz78q82`
  - name: `rude-teal-op1l`
  - project: `01knbq8tg7mmn55wf88erpv90b`
  - reported file count: `294671`
  - reported size: `5863356899` bytes

This fork is the exact stack-preservation layer for:

- leader/assistant hierarchy
- persisted OpenClaw memory and thread state
- skills, plugins, and local wrappers
- `.openclaw`, `.nemoclaw`, workspace repos, helper services, and copied credentials that already exist on disk

The empty placeholder target studio `01knbqaeqfkr0j62rvzdxcp0ek` was deleted so the new project now contains only the exact cloned cloudspace.

Repo variable state now reflects that fork:

- `TARGET_LIGHTNING_*` points at `01knbvzmj0ttzzpdndcbz78q82`
- `LIGHTNING_*` also points at `01knbvzmj0ttzzpdndcbz78q82`
- `SOURCE_LIGHTNING_*` still points at the original source studio for provenance

## Current blocker

The runtime workflows still fail before applying the copied stack because Lightning refuses to start a machine in either the source or the target project:

- workflow run: `23975334968`
- workflow run: `23975568929`
- action: `blocked_insufficient_balance`
- source studio: `01kmn9avp59m90qykz5c3ta2as`
- target studio: `01knbvzmj0ttzzpdndcbz78q82`
- target project: `01knbq8tg7mmn55wf88erpv90b`

## Strong evidence for the real cause

Lightning reports all of the following at the same time:

- source project `01kjsr1b8s8zkck9x8t7hdsvgx`
  - membership `free_credits_enabled = True`
  - membership `balance = 0.0`
- target project `01knbq8tg7mmn55wf88erpv90b`
  - membership `free_credits_enabled = False`
  - membership `balance = 0.0`

The stale source-project cloudspaces that were inflating storage were deleted:

- `01kmd44np6ph8bc59m3ja9jnkt` `parameter-golf`
- `01kmd74psbxnxdbbwv54zskc1p` `parameter-golf-t4-v2`
- `01kmd6p9b24804013reh0nea5t` `parameter-golf-g4dn-check`
- `01kmd6mh7t65g70ewyb0k528a4` `parameter-golf-t4-check`
- `01kmnags6t9p4nd3sxvy3w4d24` duplicate zero-size `rude-teal-op1l-wnfj`

After those deletes, Lightning still returns the same machine-start failure:

- `creating cloud space instance: insufficient balance to start the cloud space`

So the remaining blocker is no longer repo drift or missing runtime secrets. It is Lightning account/project state during machine startup.

## Operational implication

The exact stack is now preserved in the new project, and the repo has the exact runtime secrets needed to re-materialize Slack plus the three-agent hierarchy.

What still cannot happen until Lightning allows a machine to start again:

- applying the exact runtime secret set onto the cloned target cloudspace
- smoke-testing the cloned stack through Slack, Lightpanda, Supermemory, NemoVideo, and the assistant hierarchy
- resuming keepalive/snapshot automation against the new project
