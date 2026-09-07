# LaunchLayer Constitution

[Documentation](../../docs/README.md)

## Core Principles

### I. One Launch Pipeline

CLI and TUI behavior MUST share the established Bash modules and launch pipeline. New modules follow dependency order, remain safe to source, and avoid parallel implementations.

### II. Portable, Deterministic Shell

The shell surface MUST support Bash 4.3+, preserve argument boundaries, honor documented configuration precedence, and avoid ambient-machine or timing-dependent behavior.

### III. Safe Host Interaction

Dry runs MUST not mutate the host. Privileged changes, process termination, Steam-library writes, system tuning, and real game launches require explicit operator intent and bounded targets.

### IV. Contract-Synchronized Interfaces

Commands, keys, help, validation, completions, templates, CLI, TUI, documentation, and tests MUST change together. Hub interfaces remain compatible with the root launcher.

### V. Isolated Verification

Tests MUST isolate HOME, XDG, Steam, and configuration roots and MUST NOT depend on a real game installation. Focused Bats or hub checks precede the appropriate full gate.

## Governance

`AGENTS.md`, `hub/AGENTS.md`, and `docs/architecture.md` define detailed authority. Safety or compatibility exceptions require rationale, regression coverage, and a constitution version update.

**Version**: 1.0.0 | **Ratified**: 2026-09-02 | **Last Amended**: 2026-09-02
