# 2026-03-30 VM Repo Correction

The VM automation was accidentally pushed into the unrelated `Rohan5commit/train-once-quant-platform` repo.

This was corrected by:
- reverting the accidental commit range from `train-once-quant-platform`
- moving the VM automation ownership into `Rohan5commit/train-once-quant-platform-handoff`
- switching the handoff repo to own:
  - the VM keepalive workflow
  - the 4-hour VM snapshot workflow
  - the SSH bootstrap scripts
  - the VM keepalive systemd service definition

The handoff repo uses SSH-based VM automation instead of the unrelated runtime repo.
