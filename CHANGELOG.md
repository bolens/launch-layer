# Changelog

All notable changes to LaunchLayer are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

[Docs index](docs/README.md) · [README](README.md) · [CLI](docs/cli.md) · [TUI](docs/tui.md) · [Architecture](docs/architecture.md) · [Third-party](docs/third-party.md) · [Release](docs/release_runbook.md) · [Changelog](CHANGELOG.md)

## [Unreleased]

### Added

- Add managed OptiScaler and OpenComposite layers, hybrid-GPU selection, and native Gamescope ReShade controls.

### Security

- Reject unsafe injector destinations, tracking identifiers, and archive traversal or link entries before modifying game files.

### Fixed

- Restore tracked injections after signals, early launch failures, and watchdog recovery from force-quit sessions.
- Clean global ValvePlug tracking and expose typed GPU and OptiScaler choices in the TUI.

## [0.13.2] - 2026-09-01

### Changed

- Limit automatic ProtonDB settings to recent, corroborated reports with strict key and value validation.
- Mark generated recommendations so later runs can reconcile stale advice without overwriting user settings.

### Fixed

- Preserve complete post-`%command%` game arguments while excluding wrapper arguments.
- Respect effective native/`FORCE_PROTON` selection and keep standard Valve Proton on Steam's default compatibility path instead of writing stale overrides.
- Recognize Arch-derived profiles and installed Steam Proton version labels during report ranking.
- Avoid redundant per-game `GAMEMODE=1` overrides.

## [0.13.1] - 2026-09-01

### Changed

- Update compatible Hub development dependencies while retaining the supported TypeScript toolchain.
- Report per-game progress during bulk Hub publish and update operations without corrupting JSON output.

### Fixed

- Canonicalize client fingerprint hashes in the same key order as Convex validation.
- Exclude Steam runtimes and tools identified by `toolmanifest.vdf` from game workflows and direct Hub operations.
- Keep the primary player-guide content visible when JavaScript enhancement succeeds.

## [0.13.0] - 2026-09-01

### Added

- Add a dependency-free, read-only MCP stdio server with game, configuration, path, cache, launch-statistics, environment, recommendation, diagnostic, and validation tools.
- Add MCP 2026 discovery support, cancellation, redacted privacy mode, and a pinned Inspector conformance target.
- Add a canonical configuration-key metadata registry shared by validation, summaries, the TUI, and Hub trust checks.
- Add accessible TUI status views, text labels, reduced-motion behavior, and deterministic visual evidence.
- Add a responsive GitHub Pages guide for players, live release and CI status, and an interactive repository-backed architecture diagram.

### Changed

- Require Bash 4.3 and verify the minimum runtime in CI.
- Lazy-load command modules for substantially faster version and help output.
- Bound Hub HTTP connection time, request time, and response size.
- Cache Steam manifests and bounded engine indexes to reduce repeated filesystem scans.
- Update the Hub dependency set and require Node 22.13 or newer.
- Make ProtonDB recommendation ranking deterministic across report and Proton version ordering.
- Make version bumps atomic and portable across GNU and BSD systems.

### Fixed

- Generate direct systemd maintenance and backup commands so failures reach the journal and unit status.
- Preserve paths containing whitespace throughout Steam discovery and preflight checks.
- Serialize config, Hub apply, completion, launch-log, and backup writes to prevent lost concurrent updates.
- Keep rapid Hub applies and same-second backups under unique recovery names.
- Validate MCP request envelopes and IDs before they reach shared worker state.
- Scope temporary-file cleanup to its owning operation and keep directory migration out of module loading.

## [0.12.0] - 2026-08-11

### Added

- TUI access to ProtonDB suggestions, per-game runtime status, hub config history, historical config application, restore merge paths, bulk INCLUDE filtering/preview, and global launch statistics

### Security

- Harden config parsing, INCLUDE containment, backup archives, fetched artifact checksum verification, hub client identity, retention limits, and dependency/action pin enforcement
- Require explicitly configured trusted ingress identity and HMAC protection for hub rate limiting
- Patch all known npm advisories in the hub dependency graph, including `js-yaml`, `brace-expansion`, PostCSS, Nano ID, and `ws`

### Fixed

- Main-menu **Doctor** shortcut (`Doctor ⚠N`) actually runs doctor (case was `Doctor:*`)
- Preserve launch tuning cleanup, standalone module loading, read-only state-cache behavior, and hub cleanup rescheduling

### Changed

- Bound hub candidate queries, prioritize recent recommendations, and expire stale client data
- Strengthen CI quality, secret, dependency-pin, and action-pin gates
- Update compatible hub dependencies while retaining exact version pins

## [0.11.0] - 2026-07-14

### Added

- CachyOS, Arch, and Bazzite launch options for DLSS swapping, shader caches, Gamescope, vkBasalt, capture tools, Wine injection, specialty runtimes, and VR workflows.
- A shared download and injection path stores third-party tools in the XDG cache with notices instead of vendoring binaries.
- The TUI exposes every supported launch key through quick toggles or typed advanced controls.
- Optional playtime logging, crash hints, and launch-exit restoration for modified files.

### Changed

- Detected defaults enable safe platform-specific tuning while dry-run output shows the selected environment.
- Hub publish and apply strip remote-execution and local-mutation keys from shared configurations.
- Overlapping wrappers and aliases are validated so each behavior has one configuration path.

### Fixed

- Nested Gamescope sessions avoid inherited `LD_PRELOAD` and skip redundant nesting.
- Special K, Flawless Widescreen, winetricks, and related injectors preserve existing files and use valid source paths.

## [0.10.0] - 2026-07-14

### Added

- Community hub config history (`--hub-history`, apply historical revisions)
- ProtonDB-based `--suggest-config` rankings
- Release runbook (`docs/release_runbook.md`) with `make bump-version` / `make check-version`

### Security

- Fail-closed hub publish/delete unless `HUB_PUBLISH_TOKEN` is set (or `HUB_ALLOW_OPEN_PUBLISH=1` for local/dev)
- Reject/strip remote-exec keys (`PRE_LAUNCH_CMD`, wrappers, `OVERRIDE_PROTON`, VRAM-hog controls) on hub publish/apply
- Harden `INCLUDE=` path containment and tar import member checks
- Rate-limit privileged hub write routes and stop keying rate limits on client fingerprint alone
- Tighten hub prefs token hygiene (`chmod 600`, never echo token values)

### Changed

- CI path filters cover docs/changelog. Shell Bats and hub lint/test run as matrices.

## [0.9.0] - 2026-06-12

### Added

- Modular `lib/` layout, TUI, backups, profiles, and broad platform detection
- LaunchLayer Hub client + Convex backend for sharing per-game configs

[Unreleased]: https://github.com/bolens/launch-layer/compare/v0.13.2...HEAD
[0.13.2]: https://github.com/bolens/launch-layer/compare/v0.13.1...v0.13.2
[0.13.1]: https://github.com/bolens/launch-layer/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/bolens/launch-layer/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/bolens/launch-layer/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/bolens/launch-layer/releases/tag/v0.11.0
[0.10.0]: https://github.com/bolens/launch-layer/releases/tag/v0.10.0
[0.9.0]: https://github.com/bolens/launch-layer/tree/2f8d8bc0dda93bf55184f24eb784d903387368b2
