# Lightning AI VM

This repo is the source of truth for VM-specific automation around the active NemoClaw Lightning Studio.

It now owns:
- the GitHub Actions keepalive workflow for the VM
- the 4-hour VM snapshot workflow
- the full NemoClaw source-to-target migration workflow
- the SSH/bootstrap scripts used to keep the VM awake and verify health
- the operational handoff notes for the VM

It does not own:
- the unrelated `Rohan5commit/train-once-quant-platform` project

Current automation:
- [.github/workflows/vm-keepalive.yml](.github/workflows/vm-keepalive.yml)
- [.github/workflows/vm-snapshot.yml](.github/workflows/vm-snapshot.yml)
- [.github/workflows/vm-supervisor.yml](.github/workflows/vm-supervisor.yml)
- [.github/workflows/migrate-nemoclaw-stack.yml](.github/workflows/migrate-nemoclaw-stack.yml)
- [.github/workflows/apply-nemoclaw-runtime.yml](.github/workflows/apply-nemoclaw-runtime.yml)

Required repo variables:
- `LIGHTNING_PROJECT_ID`
- `LIGHTNING_STUDIO_ID`
- `LIGHTNING_STUDIO_NAME`
- `LIGHTNING_VM_TARGET`
- `TARGET_LIGHTNING_PROJECT_ID`
- `TARGET_LIGHTNING_STUDIO_ID`
- `TARGET_LIGHTNING_STUDIO_NAME`
- `TARGET_LIGHTNING_VM_TARGET`
- `SOURCE_LIGHTNING_PROJECT_ID`
- `SOURCE_LIGHTNING_STUDIO_ID`
- `SOURCE_LIGHTNING_STUDIO_NAME`
- `SOURCE_LIGHTNING_VM_TARGET`

Required repo secrets:
- `LIGHTNING_USERNAME`
- `LIGHTNING_API_KEY`
- `LIGHTNING_VM_SSH_KEY`
- `NEMOCLAW_SLACK_BOT_TOKEN`
- `NEMOCLAW_SLACK_APP_TOKEN`
- `NEMOCLAW_SLACK_VERIFICATION_TOKEN`
- `NEMOCLAW_NVIDIA_API_KEY_LEADER`
- `NEMOCLAW_NVIDIA_API_KEY_ASSISTANT1`
- `NEMOCLAW_NVIDIA_API_KEY_ASSISTANT2`
- `NEMOCLAW_SUPERMEMORY_API_KEY`
- `NEMOCLAW_NEMO_TOKEN`

Current docs:
- [docs/2026-03-29-lightning-studio-keepalive.md](docs/2026-03-29-lightning-studio-keepalive.md)
- [docs/2026-03-30-lightning-nemo-hardening.md](docs/2026-03-30-lightning-nemo-hardening.md)
- [docs/2026-03-30-vm-repo-correction.md](docs/2026-03-30-vm-repo-correction.md)
