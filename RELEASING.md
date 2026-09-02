# Release playbook

The authoritative LaunchLayer procedure is
[`docs/release_runbook.md`](docs/release_runbook.md). It covers the shell and
hub gates, `LAUNCHLAYER_VERSION`, changelog preparation, protected squash-merge
flow, tagging, publication, Pages verification, and recovery.

Use that runbook for every `vX.Y.Z` release. Run its complete validation
checks, never push directly to protected `main`, and verify every published
artifact and Pages surface. This root entry exists so release
instructions are discoverable at the same path across the fleet. Where this
file and the project runbook differ, the project runbook is authoritative and
must be corrected in the same pull request.

Fleet policy: <https://github.com/bolens/.github/blob/main/RELEASING.md>.
