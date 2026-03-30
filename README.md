# Train-Once Quant Platform Handoff

This repo is the source of truth for VM-specific automation around the active NemoClaw Lightning Studio.

It now owns:
- the GitHub Actions keepalive workflow for the VM
- the 4-hour VM snapshot workflow
- the SSH/bootstrap scripts used to keep the VM awake and verify health
- the operational handoff notes for the VM

It does not own:
- the unrelated `Rohan5commit/train-once-quant-platform` project

Current automation:
- [.github/workflows/vm-keepalive.yml](.github/workflows/vm-keepalive.yml)
- [.github/workflows/vm-snapshot.yml](.github/workflows/vm-snapshot.yml)

Current docs:
- [docs/2026-03-29-lightning-studio-keepalive.md](docs/2026-03-29-lightning-studio-keepalive.md)
- [docs/2026-03-30-lightning-nemo-hardening.md](docs/2026-03-30-lightning-nemo-hardening.md)
- [docs/2026-03-30-vm-repo-correction.md](docs/2026-03-30-vm-repo-correction.md)
