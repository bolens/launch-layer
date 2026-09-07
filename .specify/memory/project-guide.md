# launch-layer Spec Kit project guide

[Documentation](../../docs/README.md)

A Bash Steam launch orchestrator with shared CLI/TUI behavior and an optional
TypeScript/Convex hub.

Read this guide with `AGENTS.md` and `.specify/memory/constitution.md` before
specifying, planning, or implementing a substantial change. It is project-owned
guidance, not an upstream-managed template.

## Source and ownership map

- `launchlayer`
- `lib/load-modules.sh`
- `lib/`
- `launch.d/`
- `test/helpers.bash`
- `hub/AGENTS.md`

## Specification and plan decisions

Identify whether the change belongs to shell orchestration, the hub, or their contract.
Preserve module dependency order and configuration precedence. Keep argv as arrays,
shared modules safe to source, and CLI/TUI behavior on one pipeline.

## Acceptance evidence

Cover missing optional tools, unusual game paths, configuration precedence, dry-run
parity, and repeated loading with isolated Steam/HOME/XDG roots. Hub changes follow
hub/AGENTS.md and preserve compatibility with the root launcher.

## Validation and operational limits

```sh
make check
make check-all
```

Start with the relevant Bats file or hub lint/test target. Do not use real game
launches, privileged tuning, process killing, or Steam-library writes as test setup.
Generated Convex files and local launch configuration are not editable contract sources.

## Working through Spec Kit

Use Spec Kit for new capabilities, architectural or security-sensitive changes,
migrations, and coordinated changes that need a written contract. Keep narrow fixes,
dependency updates, and prose maintenance in the normal PR workflow.

For a new feature, record observable acceptance criteria in `spec.md`, source ownership
and constitution checks in `plan.md`, and evidence-bearing work in `tasks.md` under the
feature directory created by Spec Kit. Resolve material unknowns before implementation.
Mark tasks complete only after their stated verification, and distinguish completed,
skipped, blocked, and manual checks. Retain completed feature documents as decision
history. Backfill finished work only when explicitly requested. Label those
specifications as retrospective baselines, record the inspected revision, and map
requirements to source and acceptance evidence. Separate observed behavior from
corrective requirements. Never imply the specification preceded its code or mark
unverified checks complete.

Keep `.specify/templates/`, `.specify/scripts/`, and generated Codex skills under their
integration manifests. Use this guide and the constitution for local customization.
Regenerate managed files through Spec Kit and verify that project-owned memory survives
updates. Follow `RELEASING.md` for push, merge, release or delivery, and recovery.

The retrospective specification register is [specs/README.md](../../specs/README.md).
