# Release Runbook

Use this checklist to publish a `vX.Y.Z` release. Do not create the tag until the release commit is on `main` and the required `ci` check passes.

[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) · [Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) · [Changelog](../CHANGELOG.md)

Use a minor version for user-visible features and a patch version for fixes, documentation, or tooling changes. The CLI version is `LAUNCHLAYER_VERSION` in `lib/cli.sh`. See [README § Testing](../README.md#testing), [architecture.md § Tests](architecture.md#tests), and [CHANGELOG.md](../CHANGELOG.md).

---

## 0. Preconditions

- [ ] Working tree is clean except for intentional release changes
- [ ] On an up-to-date `main` (or a `release/vX.Y.Z` branch cut from `main`)
- [ ] You know the target version
- [ ] Local tools available: `bash`, `bats`, `shellcheck`, Node **22.13+** + pnpm (for hub gates)

`main` requires a pull request and the **`ci`** status check, including for
administrators. Squash-merge the release PR; never push straight to `main` or
bypass protection.

---

## 1. Local preflight (required)

```bash
# Shell gate (shellcheck + staged-secret check + bats)
make check

# Hub gate (eslint/tsc + unit + convex tests)
make check-hub

# Or both:
make check-all

# Network-backed MCP conformance check when MCP surfaces changed:
make check-mcp-inspector

# Static Pages structure, JavaScript, links, and accessibility hooks:
make check-pages
```

Do **not** skip `make check` / `make check-hub`. Fix failures before bumping.

After merging a site change, confirm that the **Pages** workflow deployed the expected commit and open the guide at `https://bolens.github.io/launch-layer/`.

---

## 2. Version bump

```bash
make bump-version VERSION=X.Y.Z
# then edit CHANGELOG.md under ## [X.Y.Z] - YYYY-MM-DD
make check-version
```

| File | What changes |
| --- | --- |
| `lib/cli.sh` | `LAUNCHLAYER_VERSION=X.Y.Z` (via `bump-version`) |
| `test/integration/cli.bats` | Reads the version dynamically; no edit required |
| `docs/tui.md` | Uses a `<version>` placeholder; no edit required |
| `CHANGELOG.md` | Move notes under `## [X.Y.Z] - YYYY-MM-DD` (**manual**) |

---

## 3. Commit and open a release PR

```bash
git checkout -b release/vX.Y.Z
git add -A
git status   # review: no secrets, no hub/.env.local, no node_modules
git commit -m "$(cat <<'EOF'
release: vX.Y.Z <short summary>

EOF
)"
git push -u origin HEAD
gh pr create --base main --title "release: vX.Y.Z" --body "$(cat <<'EOF'
## Summary
- Bump \`LAUNCHLAYER_VERSION\` to X.Y.Z
- Update CHANGELOG

## Test plan
- [ ] CI \`ci\` gate green
- [ ] \`./launchlayer --version\` reports X.Y.Z

EOF
)"
```

---

## 4. Wait for CI, then merge

```bash
gh pr checks <n> --watch
gh pr merge <n> --merge --delete-branch
git checkout main && git pull origin main
```

Do **not** tag while the required **`ci`** check is red.

---

## 5. Tag and publish the GitHub release

```bash
git tag -a "vX.Y.Z" -m "vX.Y.Z"
git push origin "vX.Y.Z"

gh release create "vX.Y.Z" --title "vX.Y.Z" --notes-file - <<EOF
See [CHANGELOG.md](https://github.com/bolens/launch-layer/blob/main/CHANGELOG.md) for details.

## Install
\`\`\`bash
git clone https://github.com/bolens/launch-layer.git ~/launchlayer
cd ~/launchlayer
./launchlayer --setup
\`\`\`
EOF
```

Verify:

```bash
gh release view vX.Y.Z
./launchlayer --version   # on main / the tag checkout
```

---

## 6. If something fails mid-release

| Failure | Action |
| --- | --- |
| Local `make check` / `check-hub` fail | Fix before opening the PR |
| CI red on the release PR | Fix on the PR branch. Do not tag. |
| Tag pushed with bad notes | Run `gh release edit vX.Y.Z …`. Retag only if unpublished and never relied upon. |
| Need a fix after publish | Prefer a new patch tag (`vX.Y.Z+1`) |

Never force-push `main`.

---

## Quick copy-paste (happy path)

```bash
git checkout main && git pull origin main
make check-all
make bump-version VERSION=X.Y.Z
# edit CHANGELOG.md
make check-version
git checkout -b release/vX.Y.Z
git add -A && git commit -m "release: vX.Y.Z …" && git push -u origin HEAD
gh pr create --fill
gh pr checks --watch
gh pr merge --merge --delete-branch
git checkout main && git pull origin main
git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z --generate-notes
```

---

## See also

- [CHANGELOG.md](../CHANGELOG.md): notes to edit before tagging
- [architecture.md § Tests](architecture.md#tests): `make check-all` / CI path filters
- [README § Testing](../README.md#testing) · [README § Contributing](../README.md#contributing)
- [Docs index](README.md)
