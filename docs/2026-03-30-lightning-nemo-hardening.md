## 2026-03-30 Lightning + Nemo Hardening

### Historical repo note
- The March 30 keepalive worker change was first pushed to `Rohan5commit/train-once-quant-platform` by mistake.
- That mistake was corrected later the same day by reverting that repo and moving VM automation ownership into `Rohan5commit/train-once-quant-platform-handoff`.

### What changed
- Hardened `lightning-studio-keepalive.yml` from a one-shot pulse into a long-lived keepalive worker.
- The workflow now:
  - keeps the existing 5-minute schedule
  - runs for up to 245 minutes
  - executes 58 keepalive cycles
  - pulses the Studio every 240 seconds
- This removes the old dependency on every individual cron tick succeeding.

### Live verification
- GitHub Actions run `23733534110` started on the new commit.
- The live Studio keepalive files updated again on the VM:
  - `heartbeat.json`
  - `pulse.json`
- Verified timestamp after the new worker started:
  - `2026-03-30T07:42:28.327718+00:00`

### NemoVideo fix
- Patched the live VM helper at `/home/zeus/content/workspace/NemoClaw/scripts/nemo-video-run.py`
- Changes:
  - increased default SSE wait time
  - decoded timeout bytes correctly
  - filtered partial text chunks better
  - returned a blocked result when Nemo reports Seedance credit/spending-limit exhaustion
- Verified live result:
  - `state: blocked`
  - blocked reason: Nemo’s own Seedance/video-generation credits or monthly spending limit are exhausted

### Slack state correction
- Updated the active Slack thread state from fake `processing` to `blocked`
- Posted a corrective Slack thread message explaining the real NemoVideo blocker
