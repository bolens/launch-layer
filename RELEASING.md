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

The native repository policy checks maintained python, javascript, css files selected by
[`.github/source-lint.json`](.github/source-lint.json) through Woodpecker on every pull request and push to `main`.
The duplicate hosted workflow is disabled after verified native cutover. Its
tracked source remains available for rollback.
Use the [shared local reproduction instructions](https://github.com/bolens/.github/blob/7603518f305fb76f7bb1b9979f2692521f633b82/docs/source-lint.md)
with the same tooling revision pinned in
[the native helper](scripts/ci/check-policy.sh). Review exclusions when adding
source files; generated and imported files retain their native validation.
Require the native repository check to pass on the current PR head before merging.

## Woodpecker Linux validation

[Woodpecker](https://woodpecker.bolens.dev/repos) runs `make check check-pages`
and the frozen-lockfile hub lint, tests and coverage gates on every pull request
and push to `main`. The existing shell and hub Docker workflows use the pinned public
Node 26 Debian image, disposable distribution tool installation and bounded
Bats concurrency. They need no secrets, Docker socket, host mounts or tuning.

### CI organization

Use the [shared purpose phases](https://github.com/bolens/.github/blob/main/docs/woodpecker-transition.md#ci-organization)
to find the existing shell, hub and site groups. `make check-all check-pages`
is the existing application composite gate; pair it with the source-policy
command below for complete validation. Focused rows expose each component.

| Phase | Check group / canonical local command | Native workflow / step | Retained hosted owner / boundary |
| --- | --- | --- | --- |
| `validate` | Shell and staged-secret checks: `make shellcheck check-hub-git check-dependency-pins` | `shell` / `verify` | PR, main push and native manual validation |
| `validate` | Full shared source policy: `bash scripts/ci/check-policy.sh` | `repository` / `source-policy` | Exact shared SourceLint 7603518. Duplicate hosted Source lint is disabled after verified native cutover |
| `validate` | Managed Spec Kit integrity: `bash scripts/ci/check-spec-kit.sh` (included in repository policy) | Existing policy step | Immutable C161 validator. Hosted PR/push validation retained during native qualification. Updater remains scheduled/manual on GitHub |
| `test` | Disposable shell suites: `make test` | `shell` / `verify` | Minimum Bash/Python and Ubuntu/macOS portability remain hosted |
| `validate` | Hub lint: `make lint-hub` | `hub` / `verify` | Frozen package-manager inputs; minimum Node validation remains hosted |
| `test` | Hub tests: `make test-hub`; coverage: `bash scripts/hub-pm.sh test:coverage` | `hub` / `verify` | Existing hosted aggregate still joins selected suites |
| `site` | Static site checks: `make check-pages` | `shell` / `verify` | Hosted CI produces the Pages artifact |
| `publish` | Explicit version/tag procedure in the [release runbook](docs/release_runbook.md) | Publication remains with its existing owner | Hosted Pages consumes the successful main CI artifact; product release and Convex deployment retain their separate authority |

Native aliases, required check names and the `CI` to `Pages` dependency stay
stable. Linux container setup helpers install tools inside disposable CI;
local development uses the commands in this index.

Run `bash scripts/woodpecker-linux.sh shell` or `hub` only inside the disposable
Debian CI container: these entry points install container tools. For local
checks, keep using `make check-all check-pages`. Node 22.13 and Python 3.9
minimum-runtime checks, Bash 4.3 builds, Ubuntu/macOS portability, hosted
supply-chain checks, Pages and administrative workflows remain on GitHub.

Require `ci/woodpecker/pr/shell` and `ci/woodpecker/pr/hub` alongside the existing
`ci` and `ci/woodpecker/pr/repository` checks. The ordinary caller skips duplicate hosted
ShellCheck/Bats jobs; external reusable shell callers retain full validation by
default. The hub's declared minimum Node version still runs lint, tests and
coverage in one hosted serial job; external reusable callers keep the original
matrix by default. The existing hosted aggregate rejects failed selected suites.

Validate the actual final-head native and retained hosted checks before merging,
then verify all merged-main native workflows and Pages publication. Validation
does not create product tags or deploy Convex; the existing hosted Pages workflow
publishes its validated CI artifact after a successful CI run.

The native repository group invokes the exact shared source selector and locked
tooling at `7603518f305fb76f7bb1b9979f2692521f633b82`, covering the configured
Python and site JavaScript/CSS sets. The `hub/*` exclusion stays owned by the
hub's existing lint and test commands. Local reproduction requires Git, Node 24,
Python 3 with venv support and ShellCheck; downloaded tools use a disposable
temporary directory. Container package installation stays in the YAML step.
The duplicate hosted Source lint workflow is disabled after verified native
cutover. Its tracked source remains available for rollback.
Require the native repository status while preserving `ci`, `hub`, `shell`,
minimum-runtime/platform checks and the CI-to-Pages artifact.

## Managed integration validation

`bash scripts/ci/check-spec-kit.sh` verifies the current Spec Kit manifests and
managed files without updating them. The existing native repository-policy
command, `bash scripts/ci/check-policy.sh`, includes this check in its existing
container and status context. It downloads only the public validator at
`bolens/.github@c161a6757130ea687def9eb1e81c6a4190488f07`, verifies its
SHA-256, limits the download to 64 KiB and 60 seconds, and bounds validation to
four minutes. Local reproduction needs Bash and Python 3 on Linux/macOS with
HTTPS access. It uses temporary files and requires no secrets or installed skill links.

Source/workflow policy now runs in Woodpecker. Duplicate GitHub policy workflows
are disabled, including manual and scheduled execution, after verified cutover.
Their tracked source remains available for rollback. The mixed
Spec Kit workflow still runs its hosted read-only PR/push validation while this
native integration is qualified on actual PR and genuine-main revisions. Its
scheduled/manual updater remains on GitHub. Preserve all current check names and
publication/platform boundaries during that qualification.
