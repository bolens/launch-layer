# Documentation

Steam launch orchestration and the optional community hub.

## Start here

| Need | Owning document |
| --- | --- |
| Use the project | [README.md](../README.md) |
| Change the repository | [AGENTS.md](../AGENTS.md) |
| Deliver or recover | [RELEASING.md](../RELEASING.md) |
| Plan substantial changes | [.specify/memory/project-guide.md](../.specify/memory/project-guide.md) |
| Non-negotiable constraints | [.specify/memory/constitution.md](../.specify/memory/constitution.md) |

## Architecture

[Architecture](architecture.md) owns module load order, configuration precedence, and the shared
CLI/TUI launch pipeline. Keep effective configuration and wrapper resolution identical in preview
and real execution. The [hub instructions](../hub/AGENTS.md) govern the separate TypeScript/Convex
server boundary.

## Deployment and recovery

[README](../README.md) owns launcher setup. [RELEASING.md](../RELEASING.md) and the [release
runbook](release_runbook.md) own distribution. Hub deployment and data changes are separate from
installing the launcher. Use [database guidance](../hub/DATABASE.md) before evolving the optional
hub contract.

## Database and state

Local launch configuration and caches are distinct from the hub database. [Hub database
guidance](../hub/DATABASE.md) maps schema ownership, client compatibility, and recovery limits.
Machine fingerprints and shared configuration can disclose user environment details, so keep
production records and credentials out of fixtures.

## Documentation maintenance

Keep decisions, invariants, failure modes, and recovery requirements in the owning document. Link to
commands, defaults, schemas, and generated catalogs instead of copying them. Change the owner and
affected references together. Update this index when adding or moving a guide, and verify relative
links and heading anchors. Historical specs and audits describe their recorded revision, not current
runtime proof. A topic without an implementation stays explicitly unimplemented.

## Topic guides

The [GitHub Pages guide](https://bolens.github.io/launch-layer/) is the main documentation for
players. This repository index covers exact commands, configuration keys, internal design,
third-party terms, and maintenance. Update the canonical page for a topic first and keep
cross-references brief.

| Doc | Audience | Covers |
|-----|----------|--------|
| [README](../README.md) | Everyone | Quick start, Steam, config overview, FAQ |
| [cli.md](cli.md) | CLI users | Command tables + config-key cheat sheets |
| [tui.md](tui.md) | Interactive users | Menus, toggles, screenshots, shortcuts |
| [architecture.md](architecture.md) | Contributors | Layout, module load order, hub API, CI filters |
| [third-party.md](third-party.md) | Everyone / legal | Licenses, purchase gates, nest Gamescope, STL relationship |
| [release_runbook.md](release_runbook.md) | Maintainers | Version bump, tag, GitHub release |
| [Changelog](../CHANGELOG.md) | Everyone | Release notes ([Keep a Changelog](https://keepachangelog.com/)) |

**Navigation line for new documentation pages:**

`[Docs index](README.md) · [README](../README.md) · [CLI](cli.md) · [TUI](tui.md) ·
[Architecture](architecture.md) · [Third-party](third-party.md) · [Release](release_runbook.md) ·
[Changelog](../CHANGELOG.md)`

### Canonical pages by topic

| Topic | Canonical | Also mention |
|-------|-----------|--------------|
| Steam launch options | [README § Steam](../README.md#integrating-with-steam-launch-options) | [cli.md](cli.md) setup |
| Config layers / keys | [README § Configuration](../README.md#configuration) | [cli.md](cli.md) key tables · [architecture.md](architecture.md) |
| MCP server | [cli.md § MCP server](cli.md#mcp-server) | [README § MCP server](../README.md#mcp-server) · [architecture.md](architecture.md) |
| Nested Gamescope / ScopeBuddy | [third-party.md § Nested Gamescope](third-party.md#nested-gamescope-scopebuddy-parity) | [cli.md § Gamescope](cli.md#gamescope-nest--extras) |
| lsfg-vk stacking | [third-party.md § lsfg-vk](third-party.md#lsfg-vk-and-layer-stacking) | [cli.md](cli.md) |
| Special K / ReShade / inject | [third-party.md](third-party.md) + [cli.md § Wine inject](cli.md#wine-inject-local-mutate-hub-stripped) | [tui.md § Advanced](tui.md#advanced-config) · [architecture.md](architecture.md) `lib/runtime/` |
| Assist-only VR (Geo11/Flat2VR/SBS) | [third-party.md](third-party.md) | Keys exist, with no DLL injection. |
| Config key and Hub trust metadata | [`share/launchlayer/config-keys.tsv`](../share/launchlayer/config-keys.tsv) | [architecture.md](architecture.md) · Bash + Convex parity is tested |
| Cutting a release | [release_runbook.md](release_runbook.md) | [CHANGELOG.md](../CHANGELOG.md) · [README § Testing](../README.md#testing) |

When adding a user-facing key or tool, update the CLI reference, the affected TUI section, the
third-party page when an upstream project is involved, and the changelog. Update this table if
ownership of the topic changes.

- [Editor setup](../.vscode/README.md)
