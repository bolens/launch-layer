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

## Woodpecker Linux validation

[Woodpecker](https://woodpecker.bolens.dev/repos) runs `make check check-pages`
and the frozen-lockfile hub lint, tests and coverage gates on every pull request
and push to `main`. The two ordinary Docker workflows use the pinned public
Node 26 Debian image, disposable distribution tool installation and bounded
Bats concurrency. They need no secrets, Docker socket, host mounts or tuning.

Run `bash scripts/woodpecker-linux.sh shell` or `hub` only inside the disposable
Debian CI container: these entry points install container tools. For local
checks, keep using `make check-all check-pages`. Node 22.13 and Python 3.9
minimum-runtime checks, Bash 4.3 builds, Ubuntu/macOS portability, hosted
supply-chain checks, Pages and administrative workflows remain on GitHub.

Require `ci/woodpecker/pr/shell` and `ci/woodpecker/pr/hub` alongside the existing
`ci` and `lint / Source lint` checks. The ordinary caller skips duplicate hosted
ShellCheck/Bats jobs; external reusable shell callers retain full validation by
default. The hub's declared minimum Node version still runs lint, tests and
coverage in one hosted serial job; external reusable callers keep the original
matrix by default. The existing hosted aggregate rejects failed selected suites.

Validate the actual final-head native and retained hosted checks before merging,
then verify both merged-main native workflows and Pages publication. Validation
does not create product tags or deploy Convex; the existing hosted Pages workflow
publishes its validated CI artifact after a successful CI run.
