# CLI reference

Run these commands in a terminal without `%command%`. Most game commands accept an AppID or a case-insensitive name fragment.

`./launchlayer --help` is the source of truth. This page adds context and groups the same commands by task.

[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) · [Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) · [Changelog](../CHANGELOG.md)

---

## Global flags

Place before subcommands:

| Flag / variable | Effect |
|-----------------|--------|
| `--quiet`, `-q` | Suppress non-fatal warnings |
| `--verbose`, `-v` | Extra debug output (`DEBUG=1`) |
| `--json` | Machine-readable output (where supported) |
| `LAUNCHLAYER_QUIET=1` | Same as `--quiet` (including during game launch) |
| `LAUNCHLAYER_CONFIG_DIR` | Override config root (parent of `launch.d/`) |
| `LAUNCHLAYER_GAMES_DIR` | Per-game `.env` directory (default: `~/.local/share/launchlayer/games`) |
| `LAUNCHLAYER_PROFILES` | Comma-separated machine profiles (or auto-detect) |
| `NO_COLOR=1` | Disable ANSI colors |

---

## Setup and health

| Command | Description |
|---------|-------------|
| `--help`, `-h` | Grouped command reference |
| `--version`, `-V` | Version and install paths |
| `--doctor [--json]` | Environment and config health check that includes `--validate-config all`. Exits non-zero when issues remain. Also prints non-critical gaming tips for GameMode, `ananicy-cpp`, Proton-CachyOS, and DLSS helpers. JSON adds `ananicy_cpp_active` and `proton_cachyos`. |
| `--setup [--completions] [--systemd] [--backup-timer] [--symlink] [--print-launch-option] [--write-local-config]` | Non-destructive onboarding |
| `--detect-environment [--json]` | Auto-detected platform, GPU, display, tools |
| `--detect-defaults [--json]` | Recommended machine-local settings |
| `--write-local-config [--force] [--dry-run]` | Persist defaults to `launch.d/local.env` |
| `--completions [status\|enable\|disable\|print] [--shell S]` | Shell tab completions |
| `--install-systemd` | Install user **maintenance** timer (`launchlayer-maintenance.timer`) |
| `--backup-timer [install\|enable\|disable\|status\|reinstall] [--dir PATH] [--keep N] [--schedule ON_CALENDAR] [--no-enable]` | Install/manage **backup** timer (`launchlayer-backup.timer`) |
| `--backup-prefs [show\|reset\|set\|set-schedule] [--json] [--reinstall-timer]` | Edit `backup.conf` retention, schedule, and includes |
| `--sysctl [status\|install]` | `vm.max_map_count` helper (install needs root) |

---

## Games and config

| Command | Description |
|---------|-------------|
| `--list-games [--configured] [--json] [--grep NAME]` | Installed games with native/EAC hints |
| `--init-appid APPID\|NAME [preset] [--force]` | Create per-game config |
| `--bulk-set-include PRESET [--all-configured\|--all-installed] [--grep NAME] [APPID\|NAME...] [--dry-run] [--json]` | Set `INCLUDE=presets/PRESET.env` on many games (TUI: **Games → Bulk change INCLUDE preset**: grep + dry-run/apply) |
| `--init-unconfigured [--preset P] [--eac-only] [--dry-run]` | Bulk-scaffold missing configs |
| `--prune-uninstalled [--dry-run] [--yes]` | Remove configs for uninstalled games; refuses to run when no readable Steam library is available |
| `--show-config APPID\|NAME [--json]` | Resolved layers, settings, launch chain |
| `--edit-appid APPID\|NAME` | Open/create per-game config in `$EDITOR` |
| `--paths APPID\|NAME [--json]` | Shader cache, compatdata, install paths |
| `--validate-config [APPID\|NAME\|all] [--json]` | Lint `.env` files |
| `--suggest-config APPID\|NAME [--apply]` | Suggest optimizations from ProtonDB reports (TUI: **Games → *Game* → Suggest from ProtonDB**) |
| `--scan-anticheat [--update-list]` | Find EAC/BattlEye vs known list |
| `--scan-detections` | Audit heuristic vs list mismatches for native builds, anticheat, and DLSS. Tips suggest `DLSS_SWAPPER=1` or `PROTON_DLSS_UPGRADE=1` when either is unset. |

---

## Runtime and diagnostics

| Command | Description |
|---------|-------------|
| `--status [AppID\|NAME] [--json]` | Runtime state, cache sizes |
| `--show-cpu-topology` | CPU summary + X3D V-Cache CCD range |
| `--cache-report [--min-gb N] [--grep NAME] [--json] [--shader-only\|--compat-only]` | Large cache directories |
| `--launch-stats [AppID\|NAME] [--json]` | Summarize `launch.log`. The TUI exposes per-game **Launch stats** and global stats under **Status** and **System & tools**. |
| `--dry-run %command%` | Print env + chain without running |
| `--pause-vram-hogs` / `--resume-vram-hogs` | Manual VRAM service control |
| `--cleanup-stale-launch [pid]` | Recover after crash or force-quit |

---

## Backup and restore

| Command | Description |
|---------|-------------|
| `--export-config [--output PATH] [--include-local] [--no-profiles] [--include-tui] [--json]` | Export config bundle (default: timestamped `launchlayer-export-*.tar.gz` in `backup_dir` from `backup.conf`, else `~/launchlayer-backups`) |
| `--backup-config [--output DIR\|PATH] [--exclude-local] [--no-profiles] [--include-tui] [--json]` | Scheduled-style backup. The default is a timestamped `launchlayer-backup-*.tar.gz` in `backup_dir` from `backup.conf`, or `~/launchlayer-backups`. `DIR` may not exist yet. Same-second collisions receive numeric suffixes. |
| `--import-config ARCHIVE [--yes] [--merge\|--replace] [--exclude-local] [--no-profiles] [--include-tui] [--json]` | Restore a bundle. It is a dry-run by default. Pass `--yes` to apply. |
| `--restore-backup [ARCHIVE\|DIR] [--dir PATH] [--list] [--appid APPID\|NAME] [--yes] [--merge\|--replace] …` | Restore from latest or chosen backup archive (replace by default) |
| `--prune-backups [--dir PATH] [--keep N] [--dry-run] [--json]` | Remove old backup archives |
| `--run-scheduled-backup [--dir PATH] [--keep N] [--json]` | Run backup + prune (used by `launchlayer-backup.timer`) |
| `--tui-prefs [show\|reset\|set] [--json]` | Edit `tui.conf` (fzf height, JSON mode, default preset, …) |

---

## MCP server

`launchlayer --mcp [--privacy standard|redacted]` runs a dependency-free stdio MCP server using Python 3.9+. It exposes read-only tools for installed games, resolved game configuration, game paths, cache usage, launch statistics, runtime status, environment detection, recommended defaults, diagnostics, and config validation.

Point an MCP client at the same LaunchLayer executable used by Steam:

```json
{
  "mcpServers": {
    "launchlayer": {
      "command": "/absolute/path/to/launchlayer",
      "args": ["--mcp"]
    }
  }
}
```

The server uses stdio only. It does not launch games, edit configuration, call the Community Hub, or expose mutation tools. Tool processes have time and output limits and honor MCP cancellation. The adapter supports both the MCP 2026 discovery flow and legacy initialization handshakes.

Standard results can contain local hardware details, game names, configuration values, and filesystem paths. Pass `--privacy redacted` to remove local paths and exact hardware identifiers before results leave the process. Game names and configuration values remain visible in both modes, so review the MCP host's data-sharing policy before enabling it with a remote model.

Maintainers can run `make check-mcp-inspector` for network-backed legacy and MCP 2026 conformance and tool-schema checks with the pinned official MCP Inspector.

---

## Community hub

Optional: local launches do not need the hub. Requires `curl` for publish/delete/apply; `jq` or `python3` for apply.

Privileged actions (`--hub-publish`, `--hub-update`, `--hub-delete`) need `publish_token` in `hub.conf` matching Convex `HUB_PUBLISH_TOKEN` (hubs fail closed unless `HUB_ALLOW_OPEN_PUBLISH=1` for local/dev). Publish rejects remote-exec keys (`PRE_LAUNCH_CMD`, `POST_LAUNCH_CMD`, wrappers, `OVERRIDE_PROTON`, VRAM-hog controls); `--hub-apply` strips those keys and unsafe `INCLUDE=` paths before writing.

| Command | Description |
|---------|-------------|
| `--hub-fingerprint [--json] [--fingerprint-level minimal\|standard\|detailed]` | Machine descriptor for matching. `minimal` is the default. Override it through `hub.conf` or the environment. |
| `--hub-publish APPID\|NAME [--note TEXT] [--config-id ID] [--all-configured] [--json]` | Upload per-game config(s); bulk mode reports per-game progress on stderr (rejects untrusted exec keys) |
| `--hub-update APPID\|NAME\|CONFIG_ID [--all-configured] [--note TEXT] [--include-new] [--json]` | Update existing shared config(s); bulk mode reports updated, created, or skipped status per game on stderr |
| `--hub-delete CONFIG_ID [--yes] [--json]` | Delete a shared config (requires publish token unless open publish is enabled) |
| `--hub-recommend APPID\|NAME [--limit N] [--json]` | Configs from similar machines |
| `--hub-search [--limit N] [--json]` | Machines most like yours |
| `--hub-apply CONFIG_ID [--history] [--dry-run] [--json]` | Download and atomically write a shared config. Existing files receive a unique backup. The command strips untrusted keys. Use `--history` for a historical version. |
| `--hub-history CONFIG_ID [--json]` | List publication history for a shared config |
| `--hub-prefs [show\|reset\|set] [--json]` | Edit `hub.conf` without the TUI (`publish_token` is never echoed) |

TUI equivalents are **Community hub** (main menu) and **[Hub] Community configs** (per-game actions). See [tui.md](tui.md). For hub internals and strip rules, see [architecture.md](architecture.md). For an overview, see [README § Community hub](../README.md#community-hub). Bulk preset changes use **`--bulk-set-include`** or **Games → Bulk change INCLUDE preset**.

---

## Upscaling / Proton forks (config keys)

Useful with Steam Launch Options managed by LaunchLayer (set in `games/<AppID>.env` or via TUI toggles). CachyOS reference: [Forcing the Latest DLSS Preset](https://wiki.cachyos.org/configuration/gaming/#forcing-the-latest-dlss-preset).

| Key | Effect |
|-----|--------|
| `DLSS_SWAPPER=1` \| `dll` | Insert `dlss-swapper` / `dlss-swapper-dll` after `game-performance` (NGX updater + presets, or presets-only after manual DLL replace) |
| `PROTON_DLSS_UPGRADE=1` | Proton-CachyOS / GE DLSS DLL upgrade. Requires those forks, not Valve Proton. |
| `PROTON_FSR4_UPGRADE=1` | FSR4 upgrade. RDNA3 GPUs auto-map to `PROTON_FSR4_RDNA3_UPGRADE`. |
| `PROTON_XESS_UPGRADE=1` | XeSS upgrade on supported forks |
| `PROTON_NVIDIA_LIBS=1` | Enable NVIDIA PhysX/CUDA libs in Proton forks |
| `PROTON_NVIDIA_LIBS_NO_32BIT=1` | 64-bit NVIDIA libs only (RTX 40-series tip) |
| `SHADER_CACHE_BOOST=1` | Raise Mesa / NVIDIA shader cache size limits (`SHADER_CACHE_BOOST_GB`, default 12) |
| `OVERRIDE_PROTON=…` | Force a compat tool (e.g. `proton-cachyos-slr`) |

`--suggest-config --apply` writes a Proton override only when the selected tool is installed. It applies all accepted recommendations as one locked, atomic update. Preview still reports unavailable tools so you can install them first.

`dlss-updater` is detected as an optional GUI tool only: it has no launch CLI. Prefer `DLSS_SWAPPER` or `PROTON_DLSS_UPGRADE` at launch time (not both, and not also via `LAUNCH_WRAPPERS=dlss-swapper`).

## Latency / Arch Gaming (config keys)

Env knobs from the [Arch Gaming wiki](https://wiki.archlinux.org/title/Gaming) (apply to native and Proton launches).

`NETWORK_TUNE` and `PIPEWIRE_LOW_LATENCY` are explicit opt-ins. Network coalescing, ring sizes, EEE, Wi-Fi power saving, and PipeWire quantum are system-specific. Detection does not enable them merely because the tools are installed.

| Key | Effect |
|-----|--------|
| `LD_BIND_NOW=1` | Eager dynamic linking (`LD_BIND_NOW=1`): can cut first-call hitch |
| `DISABLE_VBLANK=1` | Mesa `vblank_mode=0` + `MESA_VK_WSI_PRESENT_MODE=immediate`. NVIDIA uses `__GL_SYNC_TO_VBLANK=0`. |
| `VKBASALT=1` | Enable vkBasalt with `ENABLE_VKBASALT=1`. Install the Vulkan layer package. |
| `VKBASALT_CONFIG_FILE=…` | Export config path for vkBasalt (see [upstream](https://github.com/DadSchoorse/vkBasalt)) |
| `LATENCYFLEX=1` | Enable LatencyFleX with `LFX=1`. Works best with `DISABLE_VBLANK=1` and the game's Reflex settings. |
| `LSFG_VK=1` | Enable [lsfg-vk](https://github.com/PancakeTAS/lsfg-vk) (GPL). Requires an owned Steam copy of *Lossless Scaling*. LaunchLayer never redistributes `Lossless.dll`. |
| `LSFG_PROCESS=…` / `LSFG_CONFIG_FILE=…` | Optional lsfg-vk process/config exports |

Layer stacking with MangoHud / vkBasalt / Gamescope can conflict: see [third-party.md](third-party.md#lsfg-vk-and-layer-stacking).

## Capture / network / Conty

| Key | Effect |
|-----|--------|
| `OBS_VKCAPTURE=1` | Prefers `obs-gamecapture` / `obs-vkcapture` after Gamescope `--` |
| `DISCORD_IPC=1` | Discord rich-presence bridge hint / wrapper when `wine-discord-ipc-bridge` (or `discord-ipc-bridge`) is on `PATH` |
| `REPLAY_CAPTURE=1` | Prefer `REPLAY_TOOL=auto\|gpu-screen-recorder\|replay-sorcery`. Only `replay-sorcery` is chain-wrapped. **gpu-screen-recorder starts externally.** |
| `BLOCK_INTERNET=1` | Best-effort `unshare -n` wrap when user namespaces allow |
| `CONTY=1` / `CONTY_PATH=…` | Wrap with Conty (32-bit container) when installed |

## Wine inject (local mutate: hub-stripped)

See [docs/third-party.md](third-party.md) for licenses. Prefer user-supplied DLL directories; optional fetch only with explicit URLs / NOTICE cache. The `hub` column in [`share/launchlayer/config-keys.tsv`](../share/launchlayer/config-keys.tsv) marks keys that remote configs may not set.

| Key | Effect |
|-----|--------|
| `SPECIAL_K=1` | `WINEDLLOVERRIDES` + optional `SPECIAL_K_SOURCE` inject |
| `SPECIAL_K_DLL` / `SPECIAL_K_SOURCE` / `SPECIAL_K_INI` | Proxy DLL name, extract dir, UsingWINE ini path |
| `SPECIAL_K_FETCH=1` + `SPECIAL_K_FETCH_URL` | Cache fetch and extraction for zip, 7z, or tar. No default mirror. |
| `SPECIAL_K_VERSION` / `INJECT_SHA256` | Cache subdirectory / required SHA-256 for remote fetches |
| `RESHADE=1` | Standalone ReShade inject (`RESHADE_SOURCE`, `RESHADE_DLL`) |
| `RESHADE_SK_VERSION` | Pin hint when both SK + ReShade enabled |
| `DEPTH3D=1` | Assist-only shader path from `DEPTH3D_SOURCE` or cache, with optional `DEPTH3D_FETCH_URL` |
| `WINETRICKS_VERBS=…` | `protontricks -q` or winetricks + resolvable prefix |
| `WINETRICKS_GUI` / `WINECFG_BEFORE` / `REGISTRY_FILES` | GUI / winecfg / `.reg` apply |
| `WINE_FSR=1` (+ strength/mode) | `WINE_FULLSCREEN_FSR*` |
| `FLAWLESS_WIDESCREEN` / `FWS_PATH` / `FWS_COLAUNCH` | User path plus vcrun2010. Co-launch does not replace `PRE_LAUNCH_CMD`. |
| `SKIF` / `SKIF_PATH` / `SKIF_LAUNCH` | SKIF path with optional one-shot launch through protontricks-launch |
| `VALVEPLUG*` | Windows Steam client assist only |
| `OPENVR_FSR=1` + `OPENVR_FSR_SOURCE` | Tracked `openvr_api.dll` swap (restored after launch) |
| `GEO11` / `FLAT2VR` / `SBS_VR*` | **Assist-only** path/HMD markers (no DLL inject) |
| `SPECIALTY_RUNTIME` | `boxtron\|luxtorpeda\|roberta` → sets `OVERRIDE_PROTON` |
| `PLAYTIME_LOG` / `CRASH_GUESS` | Optional playtime log and crash retry prompt. `CRASH_GUESS=1` defaults to a five-second timeout. |

## Gamescope nest / extras

| Key | Effect |
|-----|--------|
| `GAMESCOPE_NESTED_FIX=1` | Default on: clear `LD_PRELOAD` for gamescope, re-apply after `--` (desktop Overlay/Steam Input) |
| `GAMESCOPE_EXTRA_ARGS=…` | Extra argv before `--` |
| `GAMESCOPE_PREFER_OUTPUT=…` | `-O` prefer-output |
| `GAMESCOPE_FRAME_LIMIT=…` | `--framerate-limit` |
| `GAMESCOPE_FILTER=nis\|fsr\|…` | `--filter` |
| `GAMESCOPE_FOCUSED_FPS` / `GAMESCOPE_UNFOCUSED_FPS` | Focused/unfocused FPS caps |
| `GAMESCOPE_ADAPTIVE_SYNC=` | Empty/`auto` detects VRR. `0`/`1` forces the value. The TUI exposes this under Advanced, not boolean flip. |

Inside gamescope-session, `GAMESCOPE=1` is skipped automatically. Details: [third-party.md](third-party.md).

## Bazzite / Deck identity & frame limits (config keys)

From [Bazzite launch options](https://docs.bazzite.gg/Gaming/launch-options-env-variables/) (also useful on other Deck-mode / gamescope sessions).

| Key | Effect |
|-----|--------|
| `DISABLE_STEAM_DECK=1` | Export `SteamDeck=0` (same as Bazzite `sd0`): restores full graphics options on titles that force Deck limits |
| `FRAME_RATE=N` | Set the API-level `DXVK_FRAME_RATE` and `VKD3D_FRAME_RATE` caps. These provide the lowest latency and require a restart to change. |

Prefer these keys over pasting `sd0` / raw DXVK vars into Steam launch options alongside LaunchLayer. Prefer `DLSS_SWAPPER=1` over Bazzite's `dlss-swapper %command%` wrapper in Steam.

On desktop session with Gamescope, Bazzite prefers external MangoHUD fps_limit for interactive caps; `GAMESCOPE_R` still sets gamescope `-r`.

---

## Shell completion

Supported shells: **bash**, **zsh**, **fish**, **nushell** (`nu`), **PowerShell** (`pwsh`), and **Oil** (`osh`, reuses bash completions).

```bash
./launchlayer --completions enable              # login shell
./launchlayer --completions enable --shell all
./launchlayer --completions print --shell bash  # for Nix/packaging
./launchlayer --completions enable --shell osh    # Oil shell
./launchlayer --completions enable --shell nu     # ~/.config/nushell/completions/
./launchlayer --completions enable --shell pwsh   # $PROFILE drop-in
```

Disable with `--completions disable`. Unknown flags suggest close matches ("Did you mean …?").

---

## See also

- [Docs index](README.md): topic → canonical page map
- [tui.md](tui.md): same commands via menus / quick toggles
- [third-party.md](third-party.md): licenses, purchase gates, nest Gamescope notes
- [architecture.md](architecture.md): dispatch, layers, hub strip rules
- [README § Configuration](../README.md#configuration): layered `.env` overview
