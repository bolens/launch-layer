# Feature specification: Layered launch resolution and optional Hub contracts

**Created**: 2026-09-05
**Status**: Retrospective baseline
**Inspected revision**: `40ddd54f14e3db3ff51adf856a5eed1b4f9d80ea`
**Input**: The owner requested a fleet-wide Spec Kit retrofit and implementation audit.

The Bash CLI, TUI, and read-only MCP adapter share launch configuration logic; an optional Convex Hub exchanges validated community configurations.

This specification records existing contracts after implementation. It does not
claim that the original work followed Spec Kit. New behavior requires a separate
change contract. Existing feature specifications remain authoritative within their
own scope.

## User scenarios and testing

### User story 1: Use the supported interface (P1)

A user selects the documented entry point.

**Acceptance**: Its outputs and failure behavior follow the source and acceptance mapping.

### User story 2: Handle invalid input (P2)

Inputs or dependencies fail validation.

**Acceptance**: The named negative fixtures retain the rejection and recovery contracts.

### User story 3: Maintain the implementation (P3)

A maintainer changes a supported contract.

**Acceptance**: Update its authoritative source, documentation, and tests together.

## Requirements

- **FR-001**: Configuration resolution MUST preserve ordered layers and per-game precedence, with INCLUDE presets constrained to the shipped tree.
- **FR-002**: Preview and status interfaces MUST report the resolved configuration without launching a game or applying runtime tuning.
- **FR-003**: CLI and TUI MUST use shared operations rather than diverging configuration and failure policy.
- **FR-004**: MCP MUST expose only allowlisted read-only operations, bound requests/results/runtime, and retain redacted privacy behavior.
- **FR-005**: Hub privileged routes MUST fail closed without configured authentication except for explicit local open-publish mode.
- **FR-006**: Hub payloads, query limits, quotas, and ranking MUST retain bounded validated schemas and deterministic failure behavior.

## Success criteria

- **SC-001**: Every requirement has a named source owner and acceptance check in `coverage.md`.
- **SC-002**: The listed native checks pass for the reviewed candidate, with unavailable environments and operational checks recorded separately.
- **SC-003**: Retrofitting preserves existing interfaces and completed specifications. Any confirmed implementation gap is corrected under an explicit requirement before it is marked complete.

## Edge cases and operational limits

No game launch, Steam configuration, runtime tuning, backup restore, Hub deployment, or community configuration publication was performed. Passing local fixtures does not prove a deployed Hub or desktop runtime.
