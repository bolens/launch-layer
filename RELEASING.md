# Release playbook

[Documentation](docs/README.md)

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

## Source lint

The Source lint workflow checks maintained python, javascript, css files selected by
[`.github/source-lint.json`](.github/source-lint.json) on every pull request
and push to `main`. Existing native checks remain part of the merge gate.
Use the [shared local reproduction instructions](https://github.com/bolens/.github/blob/7603518f305fb76f7bb1b9979f2692521f633b82/docs/source-lint.md)
with the same tooling revision pinned in
[the workflow](.github/workflows/source-lint.yml). Review exclusions when adding
source files; generated and imported files retain their native validation.
Require the new check to pass on the current PR head before merging.
