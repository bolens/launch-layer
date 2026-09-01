# shellcheck shell=bash
# lib/load-modules.sh — Shared source order for modular lib/ trees.
#
# Requires LIB_DIR (and CONFIG_DIR for modules that read config paths).
# Call after lib/common.sh and lib/keys.sh.

[[ -n "${LAUNCHLAYER_LOAD_MODULES_LOADED:-}" ]] && return 0
LAUNCHLAYER_LOAD_MODULES_LOADED=1

# launchlayer_source_platform — Portable helpers, OS/desktop detection, profiles.
launchlayer_source_platform() {
	# shellcheck source=platform/paths.sh
	source "$LIB_DIR/platform/paths.sh"
	# shellcheck source=platform/os.sh
	source "$LIB_DIR/platform/os.sh"
	# shellcheck source=platform/steam-detect.sh
	source "$LIB_DIR/platform/steam-detect.sh"
	# shellcheck source=platform/gpu.sh
	source "$LIB_DIR/platform/gpu.sh"
	# shellcheck source=platform/desktop.sh
	source "$LIB_DIR/platform/desktop.sh"
	# shellcheck source=platform/profiles.sh
	source "$LIB_DIR/platform/profiles.sh"
}

# launchlayer_source_compositors — JSON parsers and per-compositor display probes.
launchlayer_source_compositors() {
	# shellcheck source=hardware/compositors/json.sh
	source "$LIB_DIR/hardware/compositors/json.sh"
	# shellcheck source=hardware/compositors/wlr.sh
	source "$LIB_DIR/hardware/compositors/wlr.sh"
	# shellcheck source=hardware/compositors/desktop.sh
	source "$LIB_DIR/hardware/compositors/desktop.sh"
}

# launchlayer_source_hardware — CPU topology and display auto-detection.
launchlayer_source_hardware() {
	# shellcheck source=hardware/cpu.sh
	source "$LIB_DIR/hardware/cpu.sh"
	launchlayer_source_compositors
	# shellcheck source=hardware/display.sh
	source "$LIB_DIR/hardware/display.sh"
}

# launchlayer_source_backup — Config bundle export, import, and archive pruning.
launchlayer_source_backup() {
	# shellcheck source=inspect/backup/common.sh
	source "$LIB_DIR/inspect/backup/common.sh"
	# shellcheck source=inspect/backup/export.sh
	source "$LIB_DIR/inspect/backup/export.sh"
	# shellcheck source=inspect/backup/import.sh
	source "$LIB_DIR/inspect/backup/import.sh"
	# shellcheck source=inspect/backup/restore.sh
	source "$LIB_DIR/inspect/backup/restore.sh"
}

# launchlayer_source_inspect — Config inspection, validation, backup bundles.
launchlayer_source_inspect() {
	[[ -n "${LAUNCHLAYER_TOOLS_LOADED:-}" ]] || source "$LIB_DIR/tools.sh"
	# shellcheck source=keys.sh
	source "$LIB_DIR/keys.sh"
	# shellcheck source=inspect/show.sh
	source "$LIB_DIR/inspect/show.sh"
	# shellcheck source=inspect/maintenance.sh
	source "$LIB_DIR/inspect/maintenance.sh"
	# shellcheck source=inspect/reports.sh
	source "$LIB_DIR/inspect/reports.sh"
	# shellcheck source=inspect/validation.sh
	source "$LIB_DIR/inspect/validation.sh"
	launchlayer_source_backup
}

# launchlayer_source_prefs — User preference paths and .conf helpers.
launchlayer_source_prefs() {
	# shellcheck source=prefs/paths.sh
	source "$LIB_DIR/prefs/paths.sh"
	# shellcheck source=prefs/backup.sh
	source "$LIB_DIR/prefs/backup.sh"
	# shellcheck source=prefs/tui.sh
	source "$LIB_DIR/prefs/tui.sh"
}

# launchlayer_source_completions — Shell completion install/remove.
launchlayer_source_completions() {
	# shellcheck source=completions/core.sh
	source "$LIB_DIR/completions/core.sh"
	# shellcheck source=completions/shells.sh
	source "$LIB_DIR/completions/shells.sh"
	# shellcheck source=completions/helpers.sh
	source "$LIB_DIR/completions/helpers.sh"
	# shellcheck source=completions/cli.sh
	source "$LIB_DIR/completions/cli.sh"
}

# launchlayer_source_setup — Doctor, onboarding, systemd, sysctl.
launchlayer_source_setup() {
	# shellcheck source=setup/sysctl.sh
	source "$LIB_DIR/setup/sysctl.sh"
	# shellcheck source=setup/systemd.sh
	source "$LIB_DIR/setup/systemd.sh"
	# shellcheck source=setup/doctor.sh
	source "$LIB_DIR/setup/doctor.sh"
	# shellcheck source=setup/onboard.sh
	source "$LIB_DIR/setup/onboard.sh"
}

# launchlayer_source_hub — Community config hub client (fingerprint, similarity, API).
launchlayer_source_hub() {
	# shellcheck source=hub/prefs.sh
	source "$LIB_DIR/hub/prefs.sh"
	# shellcheck source=hub/fingerprint.sh
	source "$LIB_DIR/hub/fingerprint.sh"
	# shellcheck source=hub/similarity.sh
	source "$LIB_DIR/hub/similarity.sh"
	# shellcheck source=hub/client.sh
	source "$LIB_DIR/hub/client.sh"
}

# launchlayer_source_steam — Steam library discovery and per-game metadata.
launchlayer_source_steam() {
	# shellcheck source=vdf.sh
	source "$LIB_DIR/vdf.sh"
	# shellcheck source=steam/library.sh
	source "$LIB_DIR/steam/library.sh"
	# shellcheck source=steam/detect.sh
	source "$LIB_DIR/steam/detect.sh"
}

# launchlayer_source_cli — Help output, JSON helpers, and subcommand registry.
launchlayer_source_cli() {
	# shellcheck source=cli/colors.sh
	source "$LIB_DIR/cli/colors.sh"
	# shellcheck source=cli/json.sh
	source "$LIB_DIR/cli/json.sh"
	# shellcheck source=cli/help.sh
	source "$LIB_DIR/cli/help.sh"
	# shellcheck source=cli.sh
	source "$LIB_DIR/cli.sh"
}

# launchlayer_source_dispatch — Domain-specific CLI verb handlers.
launchlayer_source_dispatch() {
	# shellcheck source=commands/dispatch-mcp.sh
	source "$LIB_DIR/commands/dispatch-mcp.sh"
	# shellcheck source=commands/dispatch-launch.sh
	source "$LIB_DIR/commands/dispatch-launch.sh"
	# shellcheck source=commands/dispatch-config.sh
	source "$LIB_DIR/commands/dispatch-config.sh"
	# shellcheck source=commands/dispatch-setup.sh
	source "$LIB_DIR/commands/dispatch-setup.sh"
	# shellcheck source=commands/dispatch-hub.sh
	source "$LIB_DIR/commands/dispatch-hub.sh"
	# shellcheck source=commands/dispatch-tui.sh
	source "$LIB_DIR/commands/dispatch-tui.sh"
	# shellcheck source=commands/dispatch.sh
	source "$LIB_DIR/commands/dispatch.sh"
}

# launchlayer_source_commands_hub — Hub CLI verbs (publish, recommend, apply).
launchlayer_source_commands_hub() {
	# shellcheck source=keys.sh
	[[ -n "${LAUNCHLAYER_KEYS_LOADED:-}" ]] || source "$LIB_DIR/keys.sh"
	# shellcheck source=commands/hub/context.sh
	source "$LIB_DIR/commands/hub/context.sh"
	# shellcheck source=commands/hub/fingerprint.sh
	source "$LIB_DIR/commands/hub/fingerprint.sh"
	# shellcheck source=commands/hub/publish.sh
	source "$LIB_DIR/commands/hub/publish.sh"
	# shellcheck source=commands/hub/delete.sh
	source "$LIB_DIR/commands/hub/delete.sh"
	# shellcheck source=commands/hub/recommend.sh
	source "$LIB_DIR/commands/hub/recommend.sh"
	# shellcheck source=commands/hub/apply.sh
	source "$LIB_DIR/commands/hub/apply.sh"
	# shellcheck source=commands/hub/history.sh
	source "$LIB_DIR/commands/hub/history.sh"
}

# launchlayer_source_runtime — Launch hooks, env tuning, wrapper chain, logging.
launchlayer_source_runtime() {
	[[ -n "${LAUNCHLAYER_TOOLS_LOADED:-}" ]] || source "$LIB_DIR/tools.sh"
	# shellcheck source=runtime/summary.sh
	source "$LIB_DIR/runtime/summary.sh"
	# shellcheck source=runtime/tuning.sh
	source "$LIB_DIR/runtime/tuning.sh"
	# shellcheck source=runtime/inject.sh
	source "$LIB_DIR/runtime/inject.sh"
	# shellcheck source=runtime/extras.sh
	source "$LIB_DIR/runtime/extras.sh"
	# shellcheck source=runtime/chain.sh
	source "$LIB_DIR/runtime/chain.sh"
	# shellcheck source=runtime/logging.sh
	source "$LIB_DIR/runtime/logging.sh"
}

# launchlayer_source_games_list_cache — Shared list-games cache paths (CLI + TUI).
launchlayer_source_games_list_cache() {
	# shellcheck source=tui/games-cache/state.sh
	source "$LIB_DIR/tui/games-cache/state.sh"
}

# launchlayer_source_tui_games_cache — Persistent game list cache for TUI menus.
launchlayer_source_tui_games_cache() {
	launchlayer_source_games_list_cache
	# shellcheck source=tui/games-cache/menu.sh
	source "$LIB_DIR/tui/games-cache/menu.sh"
	# shellcheck source=tui/games-cache/loader.sh
	source "$LIB_DIR/tui/games-cache/loader.sh"
}

# launchlayer_source_tui_menus_backup — Backup hub TUI menus.
launchlayer_source_tui_menus_backup() {
	# shellcheck source=tui/menus-backup/settings.sh
	source "$LIB_DIR/tui/menus-backup/settings.sh"
	# shellcheck source=tui/menus-backup/transfer.sh
	source "$LIB_DIR/tui/menus-backup/transfer.sh"
	# shellcheck source=tui/menus-backup/actions.sh
	source "$LIB_DIR/tui/menus-backup/actions.sh"
	# shellcheck source=tui/menus-backup/timer.sh
	source "$LIB_DIR/tui/menus-backup/timer.sh"
	# shellcheck source=tui/menus-backup/restore.sh
	source "$LIB_DIR/tui/menus-backup/restore.sh"
	# shellcheck source=tui/menus-backup/menu.sh
	source "$LIB_DIR/tui/menus-backup/menu.sh"
}

# launchlayer_source_commands — CLI subcommands and dispatch.
launchlayer_source_commands() {
	launchlayer_source_hub
	launchlayer_source_games_list_cache
	# shellcheck source=commands/status.sh
	source "$LIB_DIR/commands/status.sh"
	# shellcheck source=commands/environment.sh
	source "$LIB_DIR/commands/environment.sh"
	# shellcheck source=commands/games.sh
	source "$LIB_DIR/commands/games.sh"
	launchlayer_source_commands_hub
	launchlayer_source_dispatch
}

# launchlayer_source_tui_hub — Community hub TUI menus.
launchlayer_source_tui_hub() {
	# shellcheck source=tui/hub/core.sh
	source "$LIB_DIR/tui/hub/core.sh"
	# shellcheck source=tui/hub/settings.sh
	source "$LIB_DIR/tui/hub/settings.sh"
	# shellcheck source=tui/hub/browse.sh
	source "$LIB_DIR/tui/hub/browse.sh"
	# shellcheck source=tui/hub/publish.sh
	source "$LIB_DIR/tui/hub/publish.sh"
	# shellcheck source=tui/hub/menu.sh
	source "$LIB_DIR/tui/hub/menu.sh"
}

# launchlayer_source_tui_system — System tools, setup, completions, and settings.
launchlayer_source_tui_system() {
	# shellcheck source=tui/menus-system-core.sh
	source "$LIB_DIR/tui/menus-system-core.sh"
	# shellcheck source=tui/menus-system-completions.sh
	source "$LIB_DIR/tui/menus-system-completions.sh"
	# shellcheck source=tui/menus-system-settings.sh
	source "$LIB_DIR/tui/menus-system-settings.sh"
	# shellcheck source=tui/settings-menu.sh
	source "$LIB_DIR/tui/settings-menu.sh"
	# shellcheck source=tui/menus-status.sh
	source "$LIB_DIR/tui/menus-status.sh"
}

# launchlayer_source_tui — Interactive terminal UI.
launchlayer_source_tui() {
	[[ -n "${LAUNCHLAYER_KEYS_LOADED:-}" ]] || source "$LIB_DIR/keys.sh"
	# shellcheck source=tui/config.sh
	source "$LIB_DIR/tui/config.sh"
	# shellcheck source=tui/spinner.sh
	source "$LIB_DIR/tui/spinner.sh"
	# shellcheck source=tui/panel.sh
	source "$LIB_DIR/tui/panel.sh"
	# shellcheck source=tui/primitives.sh
	source "$LIB_DIR/tui/primitives.sh"
	# shellcheck source=tui/glyphs.sh
	source "$LIB_DIR/tui/glyphs.sh"
	# shellcheck source=tui/help.sh
	source "$LIB_DIR/tui/help.sh"
	# shellcheck source=tui/fzf.sh
	source "$LIB_DIR/tui/fzf.sh"
	launchlayer_source_tui_games_cache
	# shellcheck source=tui/pickers.sh
	source "$LIB_DIR/tui/pickers.sh"
	# shellcheck source=tui/menus-game.sh
	source "$LIB_DIR/tui/menus-game.sh"
	# shellcheck source=tui/menus-config.sh
	source "$LIB_DIR/tui/menus-config.sh"
	launchlayer_source_tui_menus_backup
	launchlayer_source_tui_hub
	launchlayer_source_tui_system
	# shellcheck source=tui/main.sh
	source "$LIB_DIR/tui/main.sh"
}

# launchlayer_load_pre_main — Modules needed before LAUNCHLAYER_MAIN_SCRIPT is set.
launchlayer_load_pre_main() {
	launchlayer_source_platform
	# shellcheck source=tools.sh
	source "$LIB_DIR/tools.sh"
}

# launchlayer_load_post_main — Remaining modules (after LAUNCHLAYER_MAIN_SCRIPT).
launchlayer_load_post_main() {
	# shellcheck source=vdf.sh
	source "$LIB_DIR/vdf.sh"
	# shellcheck source=config.sh
	source "$LIB_DIR/config.sh"
	launchlayer_source_steam
	launchlayer_source_hardware
	# shellcheck source=detected-defaults.sh
	source "$LIB_DIR/detected-defaults.sh"
	# shellcheck source=gpu.sh
	source "$LIB_DIR/gpu.sh"
	# shellcheck source=preflight.sh
	source "$LIB_DIR/preflight.sh"
	launchlayer_source_runtime
	# shellcheck source=vram.sh
	source "$LIB_DIR/vram.sh"
	launchlayer_source_inspect
	launchlayer_source_cli
	launchlayer_source_prefs
	launchlayer_source_completions
	launchlayer_source_setup
	launchlayer_source_commands
	launchlayer_source_tui
	# shellcheck source=launch.sh
	source "$LIB_DIR/launch.sh"
}
