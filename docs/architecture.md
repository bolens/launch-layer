# LaunchLayer architecture

LaunchLayer is a bash orchestration layer for Steam game launches. The repo separates **shipped config**, **user data**, and **runtime state**.

[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) · [Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) · [Changelog](../CHANGELOG.md)

## Directory layout

```
launchlayer                 # entrypoint (sources lib via load-modules.sh)
lib/
  load-modules.sh           # module load order
  common.sh                 # paths: LAUNCHD_DIR, GAMES_DIR, launchlayer_share_dir()
  platform/                 # OS, GPU, Steam detection, profiles
  steam/                    # library discovery, native/EAC/engine detection
  hardware/                 # CPU topology, compositors/, display
  config.sh                 # layer loading, games path helpers
  hub/                      # community hub client (fingerprint, HTTP, similarity)
  inspect/                  # show, validate, backup/, maintenance
  prefs/                    # backup.conf + tui.conf path helpers (hub.conf paths in lib/hub/)
  setup/                    # doctor, sysctl, systemd, onboard
  commands/                 # status, games, hub/, dispatch-*.sh
  completions/              # shell completion installers
  cli/                      # colors, json, help, and cli.sh version/flags
  tui/                      # primitives, games-cache/, menus-backup/, hub/, main loop
hub/                        # Convex backend for community config sharing (optional)
share/launchlayer/
  templates/                # backup.conf, tui.conf, hub.conf examples
  sysctl/                   # vm.max_map_count drop-ins
  systemd/                  # maintenance + backup user unit templates
  completions/              # bash, zsh, fish, nu, pwsh scripts
launch.d/                   # shipped layers only (presets, profiles, lists)
examples/games/             # tracked example per-game configs
docs/                       # index: [docs/README.md](README.md)
  architecture.md           # this file
  cli.md                    # CLI command reference
  tui.md                    # TUI menus + screenshots (assets/tui-*.png)
  third-party.md            # upstream licenses, purchase gates, nest Gamescope notes
  release_runbook.md        # version bump + GitHub release checklist
  assets/                   # logo + TUI screenshots (regenerate: make tui-screenshots)
scripts/tui-screenshots/    # VHS capture scripts
```

`lib/runtime/` includes `tuning.sh` (env), `chain.sh` (wrappers), `inject.sh` (cache/NOTICE/track), and `extras.sh` (Special K, ReShade, Conty, VR, winetricks, …). Upstream license policy: [third-party.md](third-party.md).

## Config layers (later overrides earlier)

Matches `load_launch_config` in `lib/config.sh`:

| Order | File | Notes |
|------:|------|-------|
| 0 | `launch.d/profiles/*.env` | `LAUNCHLAYER_PROFILES` or auto-detected |
| 1 | `launch.d/default.env` | Global infrastructure defaults |
| 2 | `launch.d/local.env` | Machine-local and gitignored. `--write-local-config` writes it. It **force-overwrites** profile/default keys. |
| 3 | `launch.d/presets/*.env` | Per-game `INCLUDE=` **or** auto `standard`/`native` when no `GAMES_DIR/<AppID>.env` |
| 4 | `games/<AppID>.env` | Per-game overrides in `GAMES_DIR` |

If a per-game file exists, auto `standard`/`native` is **not** loaded, only that file (+ optional `INCLUDE=` chain).

After file layers, `apply_defaults` and `apply_detected_defaults` fill unset keys.

Per-game `INCLUDE=` loads the preset **under** that file's keys (preset first, then per-game overrides). `INCLUDE=` paths must be relative under `launch.d/`: absolute paths and `..` segments are rejected (validation + loader).

## CLI and TUI parity

Utility subcommands are implemented once in `lib/commands/` and `lib/inspect/`, then wired through:

- **CLI**: `handle_subcommand` in `lib/commands/dispatch.sh`. `launchlayer --help` is the full reference. See [docs/cli.md](cli.md).
- **TUI**: menus under `lib/tui/` call the same functions, including `show_doctor`, `hub_publish_config`, and `bulk_set_include_preset`. See [docs/tui.md](tui.md).
- **MCP**: `scripts/launchlayer-mcp.py` provides a read-only stdio adapter over JSON-producing CLI commands. `lib/commands/dispatch-mcp.sh` starts it through `launchlayer --mcp`. It supports the MCP 2026 discovery flow and legacy initialization, uses argv arrays, validates input, caps requests and results, bounds tool runtimes, honors cancellation, and does not expose launch or mutation commands. Redacted privacy mode removes local paths and exact hardware identifiers at the adapter boundary.

User preferences follow the same pattern for all three config files:

| File | CLI | TUI |
|------|-----|-----|
| `tui.conf` | `--tui-prefs` | **Settings → Interface** |
| `backup.conf` | `--backup-prefs` | **Backup & restore → Settings** |
| `hub.conf` | `--hub-prefs` | **Community hub → Hub settings** |

Bulk preset changes: **`--bulk-set-include PRESET`** or **Games → Bulk change INCLUDE preset**.

Per-game launch.d keys appear under **Quick toggles** for every 0/1 flag and **Advanced config** for every remaining string or numeric key. `$EDITOR` remains available. See [docs/tui.md](tui.md#quick-toggles).

CLI and TUI per-game edits share `appid_env_upsert` in `lib/config.sh`. Hub apply uses the same module's whole-file replacement path. Both writers use an adjacent temporary file for atomic replacement and serialize concurrent edits with `flock` when available. Hub apply gives every backup a unique suffix, including repeated applies within one second.

Completion installation serializes manifest and shell-profile edits with per-file locks when `flock` is available. Manifest and profile rewrites use adjacent, uniquely named temporary files before replacement.

## Path variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `LAUNCHLAYER_CONFIG_DIR` | repo root | Parent of `launch.d/` |
| `LAUNCHLAYER_GAMES_DIR` | `~/.local/share/launchlayer/games` | Per-game `.env` files |
| `XDG_CONFIG_HOME/launchlayer/` | user prefs | `backup.conf`, `tui.conf`, `hub.conf` |
| `XDG_STATE_HOME/launchlayer/` | runtime | launch logs, PID files, cache-check stamps |

## Module loading

`launchlayer` sources `load-modules.sh` and calls:

- `launchlayer_load_pre_main`: platform + tools (before main script path is set)
- `launchlayer_load_post_main`: remaining modules in dependency order

Subtree loaders (`launchlayer_source_steam`, `launchlayer_source_cli`, `launchlayer_source_compositors`, `launchlayer_source_backup`, `launchlayer_source_dispatch`, `launchlayer_source_tui_hub`, `launchlayer_source_tui_system`, etc.) source leaf modules directly, no thin orchestrator files.

Each leaf file uses a load guard (`LAUNCHLAYER_*_LOADED`) so tests can load individual subtrees via `source_lib` in `test/helpers.bash`.

## Steam discovery and scanning

Steam library discovery treats an explicit `STEAM_ROOT` as authoritative. Within a process, library roots, manifests, parsed manifest fields, and resolved install directories are cached so list and scan commands do not repeatedly read the same VDF files. Full-library scans seed these caches before invoking per-game callbacks. Enumeration stops if a callback fails. Destructive config pruning also refuses to run when no readable Steam library is available, keeping a discovery failure distinct from a valid empty library.

Engine detection builds one depth-bounded filesystem index per install and evaluates the ordered marker rules against it. The index includes supported macOS app-bundle roots and is capped at 50,000 entries; when an install exceeds that bound, detection falls back to the original per-rule filesystem probes so the memory guard cannot create false negatives.

## Launch pipeline

`run_game_launch` in `lib/launch.sh`:

1. Recover stale VRAM state
2. Resolve AppID → load config layers → defaults → detected defaults
3. Game flags, hardware defaults, `GAME_EXTRA_ARGS`
4. Preflight (skipped when `BENCHMARK=1`)
5. Tool warnings + anticheat guardrails
6. Pause VRAM hogs + exit trap (when enabled)
7. Runtime tuning (network, PipeWire, CPU perf, NVIDIA, Proton env, disk/HDR/malloc)
8. `build_launch_chain` → exec with pre/post hooks → log

Dry-run (`--dry-run`) loads the same config path and applies env-only tuners (HDR, malloc, Proton override) so the printed chain matches a live launch. It skips host mutations such as network and disk sysfs changes.

Launch-log rotation and append share one lock when `flock` is installed. Without `flock`, LaunchLayer appends without rotation so concurrent exits cannot lose a launch record.

Wrapper order (`lib/runtime/chain.sh`): `LAUNCH_WRAPPERS_BEFORE` → `gamemoderun` → `taskset` → `game-performance` → `dlss-swapper` (when `DLSS_SWAPPER=1` or `dll`) → `LAUNCH_WRAPPERS` → `gamescope` (optional `--mangoapp`) → `mangohud`.

Validation rejects listing `dlss-swapper` / `dlss-swapper-dll` in `LAUNCH_WRAPPERS*` while `DLSS_SWAPPER` is enabled (same pattern as `GAMEMODE` vs `gamemoderun`).

Proton env applies only configured overrides and optional CachyOS-oriented knobs: `SHADER_CACHE_BOOST`, `PROTON_*_UPGRADE` (GE/CachyOS/EM), and `PROTON_NVIDIA_LIBS*`. LaunchLayer does not force renderer, sync, feature-level, Wayland, or vendor-driver overrides for every title. Shared launch env tuning (native + Proton) applies configured Arch Gaming knobs: `LD_BIND_NOW`, `VKBASALT`/`ENABLE_VKBASALT`, `LATENCYFLEX`/`LFX`, `DISABLE_VBLANK`, plus Bazzite-oriented `DISABLE_STEAM_DECK`/`SteamDeck=0` and `FRAME_RATE` → `DXVK_FRAME_RATE`/`VKD3D_FRAME_RATE`. Doctor surfaces GameMode vs `ananicy-cpp`, Proton-CachyOS / dlss-updater, AMD RADV / sched_ext, Arch latency, and Bazzite/immutable Deck + frame-limit tips.

Compat tools resolve under Steam's user `compatibilitytools.d` and `/usr/share/steam/compatibilitytools.d` (distro Proton-CachyOS packages). Upscaling paths ([CachyOS wiki](https://wiki.cachyos.org/configuration/gaming/#forcing-the-latest-dlss-preset)):

| Mechanism | Role |
|-----------|------|
| `DLSS_SWAPPER=1` | Launch wrapper `dlss-swapper` (NGX updater + latest SR/RR/FG presets) |
| `DLSS_SWAPPER=dll` | Launch wrapper `dlss-swapper-dll`, for presets only after manual DLL replacement |
| `PROTON_*_UPGRADE` | Fork-native DLL downloaders (GE / CachyOS / EM) |
| `dlss-updater` | GUI-only offline updater. LaunchLayer detects it and prints tips but never executes it. |

Prefer one live DLSS path per game (`DLSS_SWAPPER` *or* `PROTON_DLSS_UPGRADE`), not both.

## Backup / export format

Exports include `manifest.json` plus:

- `launch.d/*`: shared layers and lists
- `games/*`: per-game configs from `GAMES_DIR`
- optional `tui.conf`

Import maps `games/*.env` into `GAMES_DIR`. Older archives that stored per-game files under `launch.d/` are imported into `GAMES_DIR` on restore.

Generated export and backup names are allocated under a directory lock when `flock` is available. If the timestamped name already exists, LaunchLayer adds a numeric suffix before `.tar.gz`. Concurrent scheduled or manual backups therefore keep both archives instead of replacing one.

## LaunchLayer Hub

Community config sharing lives in two parts:

1. **CLI client** (`lib/hub/`): machine fingerprinting, weighted similarity scoring, and HTTP calls to the hub API.
2. **Hub service** (`hub/`): Convex backend with HTTP routes for publish, recommend, similar-machines, and config download.

Configure the client in `~/.config/launchlayer/hub.conf` (template: `share/launchlayer/templates/hub.conf.example`):

```
hub_url=https://your-deployment.convex.site
machine_label=My gaming PC
publish_token=
```

CLI commands:

| Command | Purpose |
|---------|---------|
| `--hub-fingerprint [--json] [--fingerprint-level minimal\|standard\|detailed]` | Normalized machine descriptor for matching |
| `--hub-publish APPID\|NAME [--note TEXT] [--config-id ID] [--all-configured]` | Upload or update per-game config(s) |
| `--hub-update APPID\|NAME\|CONFIG_ID [--all-configured] [--include-new]` | Update existing shared config(s) for this machine |
| `--hub-delete CONFIG_ID [--yes]` | Delete a shared config (requires publish token) |
| `--hub-recommend APPID\|NAME [--limit N]` | Configs from similar machines |
| `--hub-search [--limit N]` | Machines most like yours |
| `--hub-apply CONFIG_ID [--history] [--dry-run]` | Download and write a shared config (or historical version) |
| `--hub-history CONFIG_ID` | List publication history for a shared config |
| `--hub-prefs [show\|reset\|set]` | Edit `hub.conf` (url, token, label, fingerprint level) |

ProtonDB suggestions (client-side, no hub required):

| `--suggest-config APPID\|NAME [--apply]` | Rank ProtonDB reports for this machine and optionally write allowlisted knobs |

Report ranking uses a deterministic score, recency tie-break, and numeric Proton version ordering. Apply skips unavailable compatibility tools and commits the accepted recommendation set under the same per-game lock used by CLI and TUI config edits.

The interactive TUI exposes the same flows under **Community hub** (main menu) and **[Hub] Community configs** (per-game actions). ProtonDB suggestions: **Games → *Game* → [Edit] Suggest from ProtonDB**.

Deploy the hub backend from `hub/` (Node **22.13+**, pnpm via `hub/package.json` `packageManager`). The repo root `package.json` is a scripts-only shim with no lockfile, so install inside `hub/`. Prefer [Vite+](https://viteplus.dev/) (`vp`) when available. Otherwise, enable [Corepack](https://nodejs.org/api/corepack.html) and use pnpm. Repo helpers: `scripts/hub-pm.sh`, `make test-hub`, `make lint-hub`.

```bash
cd hub
# With Vite+ (preferred):
vp install
vp run dev              # development (convex dev)
vp run lint             # ESLint + tsc
vp run convex:deploy    # production only

# Without Vite+ (Corepack + pnpm):
corepack enable
pnpm install
pnpm dev
pnpm run lint
pnpm run convex:deploy
```

Point `hub_url` at the Convex HTTP actions URL.

**Publish authentication** (fail closed): privileged routes (`POST /api/publish`, `POST /api/delete`) require `Authorization: Bearer <token>` matching Convex env `HUB_PUBLISH_TOKEN`. The client sends the same value from `publish_token` in `hub.conf` and probes `GET /api/auth` before privileged commands. If `HUB_PUBLISH_TOKEN` is unset, privileged routes are **rejected** unless `HUB_ALLOW_OPEN_PUBLISH=1` is set explicitly (local/dev only).

```bash
# Generate a token
openssl rand -hex 32

# Set on Convex (dev or prod deployment)
cd hub && npx convex env set HUB_PUBLISH_TOKEN '<your-token>'
npx convex env set HUB_TRUSTED_CLIENT_IP_HEADER 'CF-Connecting-IP'
npx convex env set HUB_IDENTIFIER_HASH_KEY "$(openssl rand -hex 32)"

# Match in ~/.config/launchlayer/hub.conf
publish_token=<your-token>

# Local open hub only (never in production):
# cd hub && npx convex env set HUB_ALLOW_OPEN_PUBLISH 1
```

Recommend, similar-machines, and config download stay public (no token required). Published `env_content` / settings may not set remote-exec or game-mutating keys listed in [`share/launchlayer/hub-untrusted-keys.txt`](../share/launchlayer/hub-untrusted-keys.txt) (wrappers, `OVERRIDE_PROTON`, VRAM-hog controls, Conty, specialty runtimes, winetricks/registry, Special K / ReShade / inject paths, VR inject toggles, Block Internet, …). Convex `HUB_UNTRUSTED_ENV_KEYS` must match that file. `--hub-apply` strips those keys and unsafe `INCLUDE=` lines before writing a local file. Config import rejects tarballs whose members use absolute or `..` paths.

Rate limits and download deduplication use HMAC-SHA-256 over one ingress-controlled client identity header. Set `HUB_TRUSTED_CLIENT_IP_HEADER` to a header that your proxy overwrites. Set `HUB_IDENTIFIER_HASH_KEY` to at least 32 random characters. The hub fails closed when either setting or the trusted header is missing. Client-supplied forwarding fallbacks are ignored and raw addresses are not stored. Rotating the HMAC key resets deduplication identities. Rate-limit buckets expire after 24 hours and download-dedup records after 30 days via a daily bounded cleanup job.

| Route | Auth | Rate limit (per client IP / min) |
|-------|------|----------------------------------|
| `GET /api/auth` | Public: returns `{ publish_auth_required: bool }` | None |
| `POST /api/publish` | Privileged. Token required unless `HUB_ALLOW_OPEN_PUBLISH=1`. Upserts by machine fingerprint + appid. Optional `config_id` updates that record when fingerprint matches. | 10 |
| `POST /api/my-config` | Public. Returns `{ config_id, published_at, downloads }` or `null` for this machine + appid. | 60 |
| `POST /api/delete` | Privileged (token required unless `HUB_ALLOW_OPEN_PUBLISH=1`) | 5 |
| `POST /api/recommend` | Public | 30 |
| `POST /api/similar-machines` | Public | 30 |
| `GET /api/config/:id` | Public | 120 |
| `GET /api/config-history/:id` | Public | 120 (same bucket as getConfig) |

Similarity scoring weights GPU vendor, OS/session, desktop compositor, display and refresh tiers, VRAM tier, monitor layout, X3D flags, profile overlap, and platform flags (Deck, Flatpak, WSL2, container, etc.) on a 0–100 scale: same algorithm in bash (`lib/hub/similarity.sh`) and TypeScript (`hub/convex/lib/similarity.ts`).

Recommendations are ranked by **similarity (desc)**, then **`published_at` (desc)** so newer configs win ties on the same hardware match, then **downloads (desc)**. `published_at` is refreshed on every republish of the same machine+game config. CLI and TUI list lines include `updated YYYY-MM-DD`; `GET /api/config/:id` also returns `published_at` and `downloads`.

**Fingerprint depth** (`fingerprint_level` in `hub.conf`, default `minimal`):

| Level | Shared data |
|-------|-------------|
| `minimal` | GPU vendor, OS, session, profiles, display/refresh tiers, desktop, platform flags |
| `standard` | minimal + audio, VRAM tier, monitor layout, aspect, exact display, X3D CPU mask |
| `detailed` | standard + full GPU list, all monitors, output names, OS id |

Override once: `LAUNCHLAYER_HUB_FINGERPRINT_LEVEL=detailed` or `--hub-fingerprint --fingerprint-level detailed`.

## Tests

```bash
make test              # bats test/integration + test/unit (parallel when GNU parallel is installed)
make test-unit         # bats test/unit
make test-integration  # bats test/integration
make check             # shellcheck + check-hub-git + bats (shell gate)
make check-hub-git     # scripts/check-staged-hub-secrets.sh
make check-dependency-pins # exact npm versions, lockfile integrity, Action SHAs
make test-hub          # hub unit + convex tests (via scripts/hub-pm.sh)
make lint-hub          # hub ESLint + tsc
make check-hub         # lint-hub + test-hub
make test-all          # shell bats + test-hub
make check-all         # check + check-hub
make bump-version VERSION=X.Y.Z
make check-version
```

CI (`.github/workflows/ci.yml`) uses path filters:

| Filter | Paths (high level) | Jobs |
|--------|--------------------|------|
| `shell` | `lib/`, `test/`, `scripts/`, `share/`, `launch.d/`, `README.md`, `docs/README.md`, `docs/cli.md`, `docs/tui.md`, `docs/third-party.md`, `docs/release_runbook.md`, … | `ci-shell.yml`: shellcheck + bats matrix (`unit`, `integration`) |
| `hub` | `hub/`, `docs/architecture.md`, `scripts/hub-pm.sh`, hub workflows, … | `ci-hub.yml`: matrix (`lint`, `test`) via `scripts/hub-pm.sh` |
| `workflows` | `.github/workflows/**` | actionlint |

`pnpm audit` is a weekly workflow (`.github/workflows/hub-audit.yml`), not part of the PR gate.

Cutting a tagged release: [release_runbook.md](release_runbook.md). User-facing CLI/TUI: [cli.md](cli.md) · [tui.md](tui.md).
