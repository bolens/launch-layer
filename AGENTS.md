# AGENTS.md

## Purpose

LaunchLayer is a Bash 4.2+ launch orchestrator for Steam games. The repository
also contains an optional Convex/TypeScript community hub under `hub/`.

Keep changes narrow, portable, and covered by the closest relevant tests.

## Instruction scope

- This file applies to the repository except where a deeper `AGENTS.md`
  overrides it.
- Work under `hub/` must follow `hub/AGENTS.md` as well as this file.
- Preserve user changes in a dirty worktree. Do not rewrite unrelated files.
- Do not modify machine-local `launch.d/local.env` unless explicitly asked.

## Repository map

- `launchlayer`: executable entrypoint and top-level dispatch.
- `lib/load-modules.sh`: canonical module dependency and source order.
- `lib/`: Bash implementation.
  - `commands/`: CLI dispatch and domain commands.
  - `runtime/`: launch chain, environment tuning, hooks, and logging.
  - `platform/`, `hardware/`, `steam/`: detection and discovery.
  - `inspect/`, `setup/`, `prefs/`, `completions/`: supporting workflows.
  - `tui/`: interactive UI; it should reuse the same domain functions as CLI.
- `launch.d/`: shipped defaults, profiles, presets, and data lists.
- `share/launchlayer/`: installed templates, completions, systemd, and sysctl
  assets.
- `test/unit/`, `test/integration/`: Bats tests.
- `hub/`: Node 22+, pnpm, Convex, TypeScript; see its local instructions.
- `docs/architecture.md`: source of truth for module and launch architecture.
- `docs/cli.md`, `docs/tui.md`: user-facing command and TUI references.

## Working conventions

### Bash

- Target Bash 4.2+; do not silently introduce newer-only features.
- Match the existing style: tabs for shell indentation, quoted expansions,
  `[[ ... ]]`, arrays for argv, and `local` variables inside functions.
- Preserve argv boundaries. Avoid constructing commands as strings or using
  `eval`; use arrays and `"${args[@]}"`.
- Keep `set -euo pipefail` behavior in mind. Handle expected nonzero statuses
  explicitly.
- Use project path helpers and XDG variables instead of hard-coded home paths.
- Treat config and hub input as untrusted. Preserve validation for paths,
  keys, numeric bounds, payload sizes, and shell values.
- New leaf modules should use the existing idempotent
  `LAUNCHLAYER_*_LOADED` guard pattern.
- Add new modules to `lib/load-modules.sh` in dependency order. Do not source
  modules ad hoc from the entrypoint.
- Add `# shellcheck source=...` annotations for statically known sources.
- Keep side effects out of module load time so tests can source subtrees.
- Optional dependencies must degrade gracefully unless the command explicitly
  requires them.

### Behavior and interfaces

- Configuration precedence is profiles → default → local → preset/per-game →
  computed defaults. Later layers win; do not change precedence accidentally.
- A per-game file suppresses the automatic preset unless it declares
  `INCLUDE=`.
- Keep CLI and TUI behavior aligned by implementing reusable logic once and
  wiring both interfaces to it.
- When adding or renaming a command/config key, inspect all affected surfaces:
  dispatch, help, validation/key registry, completions, TUI, templates,
  examples, docs, and tests.
- Dry-run paths must not mutate the host and should resolve the same effective
  environment and wrapper chain as a real launch.
- Do not perform privileged, systemd, sysctl, process-killing, Steam-library,
  or real game-launch operations during tests. Use temp roots and mocks.
- Never commit tokens, private hub keys, machine fingerprints, personal Steam
  data, runtime state, or generated local configuration.

### Tests

- Put focused behavior tests in the matching `test/unit/*.bats` file.
- Use integration tests for entrypoint dispatch and cross-module workflows.
- Reuse `test/helpers.bash`; isolate `HOME`, XDG paths, Steam roots, and config
  roots with temporary directories.
- Tests within a Bats file may share setup state, so keep them serial-safe.
- Add regression coverage for bug fixes, including the failing edge case.
- Avoid timing-sensitive assertions and dependence on the developer machine.

## Validation commands

Run the smallest relevant checks while iterating, then the broader gate for the
areas changed.

```bash
# One Bats file
bats test/unit/<area>.bats
bats test/integration/<area>.bats

# Shell suites
make test-unit
make test-integration
make shellcheck
make check

# Hub suites (also available as make lint-hub / test-hub)
bash scripts/hub-pm.sh lint
bash scripts/hub-pm.sh test

# Everything
make check-all
```

`make check` is the root shell CI gate: ShellCheck, staged hub-secret scan, and
all Bats tests. `make check-all` adds hub lint and tests. If a required tool is
unavailable, report which checks were not run rather than weakening tests.

## Documentation and generated artifacts

- Update user-facing docs when flags, config keys, output, workflows, or TUI
  behavior change.
- Update `docs/architecture.md` when module boundaries, load order, config
  precedence, or the launch pipeline changes.
- Keep README examples and shipped templates consistent with implementation.
- Regenerate TUI screenshots only for intentional visual changes with
  `make tui-screenshots`; review the resulting binary changes.
- Do not hand-edit generated Convex files under `hub/convex/_generated/`.
- Do not change dependency lockfiles unless dependencies actually changed.

## Before handing off

- Review `git diff` for unrelated changes, secrets, local paths, and generated
  noise.
- Run and report the checks appropriate to the changed scope.
- Summarize behavior changes and call out any validation not completed.
