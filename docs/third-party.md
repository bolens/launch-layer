# Third-party tools and licenses

LaunchLayer is licensed under [CC BY-NC-SA 4.0](../LICENSE). Integrations invoke or optionally cache upstream tools. They **do not** relicense those projects or vendor binaries into the LaunchLayer source tree.

[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) · [Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) · [Changelog](../CHANGELOG.md)

Auto-fetched artifacts (when enabled) live under `~/.local/share/launchlayer/cache/<tool>/` with a `NOTICE` file (upstream URL, version, SPDX/license). Prefer distro packages when available. See [architecture.md](architecture.md) (`lib/runtime/inject.sh`, `extras.sh`) for the cache/inject path.

## Policy

- **Invoke** installed tools when possible (`PATH`, Vulkan layers).
- **Never commit** third-party binaries to this repository.
- **Purchase / EULA gates**: tools that require a separate purchase (e.g. Steam *Lossless Scaling* for lsfg-vk) must be owned by the user: LaunchLayer never downloads proprietary `Lossless.dll`.
- **Hub configs** strip mutate / remote-exec keys (inject paths, winetricks, wrappers, etc.).
- Names are used for identification only. No endorsement is claimed.

## Supported tools

Verify licenses upstream because they can change.

| Tool | Upstream | Typical license | How LaunchLayer uses it |
|------|----------|-----------------|-------------------------|
| GameMode | [FeralInteractive/gamemode](https://github.com/FeralInteractive/gamemode) | BSD-3-Clause | `GAMEMODE` → `gamemoderun` |
| Gamescope | [ValveSoftware/gamescope](https://github.com/ValveSoftware/gamescope) | BSD-2-Clause | `GAMESCOPE` chain + nest `LD_PRELOAD` fix |
| MangoHud | [flightlessmango/MangoHud](https://github.com/flightlessmango/MangoHud) | MIT | `MANGOHUD` / `--mangoapp` |
| vkBasalt | [DadSchoorse/vkBasalt](https://github.com/DadSchoorse/vkBasalt) | zlib | `VKBASALT` → `ENABLE_VKBASALT`, with optional `VKBASALT_CONFIG_FILE` |
| LatencyFleX | community packages | varies | `LATENCYFLEX` → `LFX` |
| lsfg-vk | [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk) | GPL-3.0 | `LSFG_VK=1`. **Requires owned Lossless Scaling.** |
| Lossless Scaling | Steam App 993090 | Proprietary | User-owned DLL only: never redistributed |
| ScopeBuddy | [OpenGamingCollective/ScopeBuddy](https://github.com/OpenGamingCollective/ScopeBuddy) | Apache-2.0 | Behaviors reimplemented, with optional `LAUNCH_WRAPPERS=scopebuddy` escape hatch |
| Special K | [SpecialKO/SpecialK](https://github.com/SpecialKO/SpecialK) | GPL-3.0 | `SPECIAL_K` env / optional cache inject (`SPECIAL_K_FETCH_URL`) |
| SKIF | [SpecialKO/SKIF](https://github.com/SpecialKO/SKIF) | per project | Optional `SKIF_PATH`, with `SKIF_LAUNCH=1` for one-shot launch |
| ValvePlug | [SpecialKO/ValvePlug](https://github.com/SpecialKO/ValvePlug) | per project (archived) | Windows Steam client only. On Linux Steam, use Controller settings. |
| ReShade | [crosire/reshade](https://github.com/crosire/reshade) | BSD-3-Clause | `RESHADE` local inject. Respect [shader redistribution rules](https://reshade.me/forum/general-discussion/771-distribution-regulations). |
| Depth3D / shaders | various | per author | **Assist-only** `DEPTH3D` paths / optional `DEPTH3D_FETCH_URL`: do not wholesale revendor |
| obs-vkcapture | [nowrep/obs-vkcapture](https://github.com/nowrep/obs-vkcapture) | GPL-2.0 | `OBS_VKCAPTURE` |
| wine-discord-ipc-bridge | community | MIT (typical) | `DISCORD_IPC` |
| ReplaySorcery | [matanui159/ReplaySorcery](https://github.com/matanui159/ReplaySorcery) | GPL-3.0 | `REPLAY_CAPTURE` (chain-wrapped) |
| gpu-screen-recorder | community | GPL | Prefer tool: **starts externally**, not chain-wrapped |
| Conty | [Kron4ek/Conty](https://github.com/Kron4ek/Conty) | verify upstream | `CONTY` wrap |
| FlawlessWidescreen | [flawlesswidescreen.org](https://www.flawlesswidescreen.org/) | Proprietary freeware (verify EULA) | User `FWS_PATH` only: never auto-download |
| OpenVR-FSR | community forks | MIT/BSD (verify) | Tracked inject + restore |
| Geo11 | community | verify | **Assist-only** path/env (`GEO11_SOURCE`): no DLL inject |
| Flat2VR / SBS-VR | community | verify | **Assist-only** path/HMD markers: no auto player launch |
| Boxtron / Luxtorpeda / Roberta | Steam compat tools | per project | `SPECIALTY_RUNTIME` → `OVERRIDE_PROTON` |
| protontricks / winetricks | community | LGPL / GPL | `WINETRICKS_VERBS`, `WINECFG_BEFORE`, `REGISTRY_FILES` |
| GOverlay | [benjamimgois/goverlay](https://github.com/benjamimgois/goverlay) | zlib | Doctor tip only (not embedded) |
| dlss-swapper | CachyOS | verify | `DLSS_SWAPPER` |

## lsfg-vk and layer stacking

`LSFG_VK` enables the lsfg-vk Vulkan layer. Combining it with **MangoHud**, **vkBasalt**, and nested **Gamescope** can produce undefined layer order or overlays fighting for the swapchain. Prefer enabling one post-process/frame-gen path per game until you have verified stacking on your setup. Lossless Scaling's proprietary DLL must already be installed from Steam: LaunchLayer never downloads it (`inject_refuse_proprietary_redistrib` / purchase gate).

## Nested Gamescope (ScopeBuddy parity)

On desktop nested Gamescope, Steam's `LD_PRELOAD` (overlay) can break Overlay / Steam Input. With `GAMESCOPE_NESTED_FIX=1` (default), LaunchLayer runs:

`env -u LD_PRELOAD gamescope … -- env LD_PRELOAD=… %command%`

Inside an existing gamescope-session (Deck gamemode), `GAMESCOPE=1` is skipped automatically.

Escape hatch: `GAMESCOPE=0` and `LAUNCH_WRAPPERS=scopebuddy` if you prefer ScopeBuddy's own config tree.

Config keys: [cli.md § Gamescope nest / extras](cli.md#gamescope-nest--extras). TUI: [tui.md § Advanced config → Gamescope](tui.md#advanced-config).

## SteamTinkerLaunch

LaunchLayer is not STL. It adopts selected tools as config keys and wrappers without the wait-menu Main Menu, mod-manager installers, or Compatibility Tool packaging.

## See also

- Config-key cheat sheets: [cli.md](cli.md) (Wine inject, capture, lsfg-vk, Gamescope)
- TUI "Inject & Wine" group: [tui.md § Advanced config](tui.md#advanced-config)
- Runtime modules: [architecture.md](architecture.md)
- Optional tool list (install hints): [README § Optional dependencies](../README.md#optional-dependencies)
- Project license: [README § License](../README.md#license) · [LICENSE](../LICENSE)
