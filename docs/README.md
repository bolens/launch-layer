# LaunchLayer documentation

User and contributor docs live here. Prefer updating the linked page for a topic rather than duplicating long explanations elsewhere.

| Doc | Audience | Covers |
|-----|----------|--------|
| [README](../README.md) | Everyone | Quick start, Steam, config overview, FAQ |
| [cli.md](cli.md) | CLI users | Command tables + config-key cheat sheets |
| [tui.md](tui.md) | Interactive users | Menus, toggles, screenshots, shortcuts |
| [architecture.md](architecture.md) | Contributors | Layout, module load order, hub API, CI filters |
| [third-party.md](third-party.md) | Everyone / legal | Licenses, purchase gates, nest Gamescope, STL relationship |
| [release_runbook.md](release_runbook.md) | Maintainers | Version bump, tag, GitHub release |
| [Changelog](../CHANGELOG.md) | Everyone | Release notes ([Keep a Changelog](https://keepachangelog.com/)) |

**Nav (paste this line into new docs pages):**

`[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) · [Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) · [Changelog](../CHANGELOG.md)`

### Topic → canonical page

| Topic | Canonical | Also mention |
|-------|-----------|--------------|
| Steam launch options | [README § Steam](../README.md#integrating-with-steam-launch-options) | [cli.md](cli.md) setup |
| Config layers / keys | [README § Configuration](../README.md#configuration) | [cli.md](cli.md) key tables · [architecture.md](architecture.md) |
| MCP server | [cli.md § MCP server](cli.md#mcp-server) | [README § MCP server](../README.md#mcp-server) · [architecture.md](architecture.md) |
| Nested Gamescope / ScopeBuddy | [third-party.md § Nested Gamescope](third-party.md#nested-gamescope-scopebuddy-parity) | [cli.md § Gamescope](cli.md#gamescope-nest--extras) |
| lsfg-vk stacking | [third-party.md § lsfg-vk](third-party.md#lsfg-vk-and-layer-stacking) | [cli.md](cli.md) |
| Special K / ReShade / inject | [third-party.md](third-party.md) + [cli.md § Wine inject](cli.md#wine-inject-local-mutate--hub-stripped) | [tui.md § Advanced](tui.md#advanced-config) · [architecture.md](architecture.md) `lib/runtime/` |
| Assist-only VR (Geo11/Flat2VR/SBS) | [third-party.md](third-party.md) | Keys exist, with no DLL injection. |
| Hub untrusted keys | [`share/launchlayer/hub-untrusted-keys.txt`](../share/launchlayer/hub-untrusted-keys.txt) | [architecture.md](architecture.md) · bash + Convex must match |
| Cutting a release | [release_runbook.md](release_runbook.md) | [CHANGELOG.md](../CHANGELOG.md) · [README § Testing](../README.md#testing) |

When you add a user-facing key or tool, update **cli + tui + third-party (if upstream) + CHANGELOG**, and keep this index's topic table honest.
