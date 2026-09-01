# Changelog

All notable changes to LaunchLayer are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/).

[Docs index](docs/README.md) · [README](README.md) · [CLI](docs/cli.md) · [TUI](docs/tui.md) · [Architecture](docs/architecture.md) · [Third-party](docs/third-party.md) · [Release](docs/release_runbook.md) · [Changelog](CHANGELOG.md)

## [Unreleased]

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

- First-class `DLSS_SWAPPER` (`1` → `dlss-swapper`, `dll` → `dlss-swapper-dll`): CachyOS wrapper in the launch chain (TUI toggle, doctor/optional-tools, detection hints)
- CachyOS gaming wiki alignment: `SHADER_CACHE_BOOST`, Proton-CachyOS/GE/EM `PROTON_*_UPGRADE` knobs, and `PROTON_NVIDIA_LIBS*`
- Arch Gaming wiki alignment: `LD_BIND_NOW`, `VKBASALT` → `ENABLE_VKBASALT`, `LATENCYFLEX` → `LFX`, `DISABLE_VBLANK`
- Bazzite docs alignment: `DISABLE_STEAM_DECK` → `SteamDeck=0`, `FRAME_RATE=N` → `DXVK_FRAME_RATE`/`VKD3D_FRAME_RATE`
- Shared inject/fetch framework (`lib/runtime/inject.sh`) with XDG cache + NOTICE files: no third-party binaries in the source tree ([docs/third-party.md](docs/third-party.md) · [docs/architecture.md](docs/architecture.md))
- Gamescope nest fix (`GAMESCOPE_NESTED_FIX`): `env -u LD_PRELOAD` around nested desktop Gamescope; skip Gamescope inside gamescope-session ([docs/third-party.md § Nested Gamescope](docs/third-party.md#nested-gamescope-scopebuddy-parity) · [docs/cli.md](docs/cli.md#gamescope-nest--extras))
- Gamescope extras: `GAMESCOPE_EXTRA_ARGS`, `GAMESCOPE_PREFER_OUTPUT`, `GAMESCOPE_FRAME_LIMIT`, `GAMESCOPE_FILTER`, focused/unfocused FPS; auto-VRR when `GAMESCOPE_ADAPTIVE_SYNC` is empty/`auto` ([docs/cli.md](docs/cli.md#gamescope-nest--extras) · [docs/tui.md](docs/tui.md#advanced-config))
- vkBasalt `VKBASALT_CONFIG_FILE` / `VKBASALT_LOG_LEVEL`; lsfg-vk (`LSFG_VK`, purchase gate for Lossless Scaling) ([docs/third-party.md](docs/third-party.md))
- Chain/env tools: `OBS_VKCAPTURE`, `DISCORD_IPC`, `REPLAY_CAPTURE`, `BLOCK_INTERNET`, `CONTY` ([docs/cli.md](docs/cli.md#capture--network--conty))
- Wine extras: `WINETRICKS_VERBS`, `WINECFG_BEFORE`, `REGISTRY_FILES`, `WINE_FSR`, Special K / ReShade / Depth3D / FWS / ValvePlug / SKIF / OpenVR-FSR / Geo11 / SBS-VR / Flat2VR / specialty runtimes ([docs/cli.md § Wine inject](docs/cli.md#wine-inject-local-mutate--hub-stripped) · [docs/tui.md](docs/tui.md#advanced-config))
- Opt-in `PLAYTIME_LOG` and `CRASH_GUESS` (default timeout 0: no STL wait-menu)
- Hub strips new mutate/remote-exec inject keys on publish/apply ([docs/architecture.md](docs/architecture.md) · [docs/cli.md § Community hub](docs/cli.md#community-hub))
- Docs index + shared nav across README / docs / CHANGELOG ([docs/README.md](docs/README.md))
- Shared `share/launchlayer/hub-untrusted-keys.txt` synced to Convex `HUB_UNTRUSTED_ENV_KEYS` (includes `CONTY`, `SPECIALTY_RUNTIME`, inject/Wine/VR mutate keys)
- Special K fetch extracts archives into a usable `SPECIAL_K_SOURCE`; launch-exit restore for tracked injects (`.ll-bak`)
- FWS vcrun2010 + non-stomping co-launch; winetricks prefix fallback; `SKIF_LAUNCH`; `DEPTH3D_FETCH_URL`; CRASH_GUESS default 5s timeout when enabled
- Assist-only labeling for Geo11 / Flat2VR / SBS-VR / Depth3D path markers, plus lsfg-vk layer stacking notes

### Changed

- Prefer `DLSS_SWAPPER=1` over `LAUNCH_WRAPPERS=dlss-swapper`; validation flags combining both; detection tips also accept `PROTON_DLSS_UPGRADE=1`
- Detected defaults enable `SHADER_CACHE_BOOST=1` off Steam Deck / WSL
- TUI quick toggles cover all boolean launch flags. Advanced config groups every remaining string/numeric key for full config-key parity.
- TUI: `DLSS_SWAPPER` cycles `0→1→dll→0` (◐ glyph for dll); `FWS` Advanced-only alias of `FLAWLESS_WIDESCREEN`; assist-only toggle labels; enum pickers for specialty runtime / replay / Gamescope filter / VRR; compact game preview (hot keys + overrides)
- Dry-run "Environment (selected)" includes Arch/Bazzite exports (`LD_BIND_NOW`, `ENABLE_VKBASALT`, `LFX`, `SteamDeck`, Mesa present mode, …)
- Config lint rejects non-integer `FRAME_RATE`; same-file `sd0` + `DISABLE_STEAM_DECK=1` flagged like other wrapper overlaps
- Flag `sd0` in `LAUNCH_WRAPPERS` when `DISABLE_STEAM_DECK=1` (use one path)

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
