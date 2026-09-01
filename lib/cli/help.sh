# shellcheck shell=bash
# lib/cli/help.sh — CLI help, version, and brief usage text.

[[ -n "${LAUNCHLAYER_CLI_HELP_LOADED:-}" ]] && return 0
LAUNCHLAYER_CLI_HELP_LOADED=1

# print_version — Version and install paths.
print_version() {
	local bn
	bn="$(cli_basename)"
	echo "LaunchLayer ${LAUNCHLAYER_VERSION}"
	echo "script=${LAUNCHLAYER_MAIN_SCRIPT:-unknown}"
	echo "config_dir=${CONFIG_DIR:-unknown}"
	echo "bash=${BASH_VERSION}"
}

# print_usage_brief — Short usage when invoked with no arguments.
print_usage_brief() {
	local bn
	bn="$(cli_basename)"
	cat <<EOF
$(cli_basename): Layered game launch orchestration and config toolkit.

Usage:
  ${bn} %command%                 Launch a game (Steam launch options)
  ${bn} --dry-run %command%       Print resolved config without running
  ${bn} --doctor                  Environment and config health check
  ${bn} --setup                   Onboarding (completions + launch option)
  ${bn} --list-games              Installed games with detection hints
  ${bn} --show-config APPID       Resolved layers and launch chain

  ${bn} --tui                       Interactive game/config browser (fzf optional)

With no arguments in a TTY, opens the TUI automatically when fzf is installed.

Run '${bn} --help' for the full command reference.
EOF
}

# print_help — Grouped command reference.
print_help() {
	local bn
	bn="$(cli_basename)"

	cat <<EOF
$(cli_bold "LaunchLayer") $(cli_dim "${LAUNCHLAYER_VERSION}")
Layered launch profiles, preflight checks, and wrapper chains for games.

$(cli_bold "Steam launch options")
  "${LAUNCHLAYER_MAIN_SCRIPT:-$bn}" %command%
  %command% is required; without it Steam never runs the game binary.

$(cli_bold "Onboarding & health")
  --doctor [--json]                 Full environment + config health check (+ gaming tips)
  --setup [--completions] [--systemd] [--backup-timer] [--symlink] [--print-launch-option]
          [--write-local-config]
  --detect-environment [--json]   Auto-detected platform, GPU, display, tools
  --detect-defaults [--json]      Recommended machine-local env settings
  --write-local-config [--force] [--dry-run]
                                    Write launch.d/local.env from detection
  --completions [status|enable|disable|print] [--shell bash|zsh|fish|nu|pwsh|osh|all] [--json]
  --install-systemd                 Install user maintenance timer
  --run-maintenance                 Run the maintenance service payload now
  --backup-timer [install|enable|disable|enable-service|disable-service|uninstall|status|reinstall] [--dir PATH] [--keep N] [--schedule ON_CALENDAR]
                                    Install/manage backup timer (prefs: ~/.config/launchlayer/backup.conf)
  --backup-prefs [show|reset|set|set-schedule] [args...] [--json] [--reinstall-timer]
                                    Manage backup preferences (keep, auto_prune, schedule, includes)
  --sysctl [status|install]         vm.max_map_count helper (install needs root)

$(cli_bold "Games & config")
  --list-games [--configured] [--json] [--grep NAME]
  --init-appid APPID|NAME [preset] [--force]  Create games/<AppID>.env
  --bulk-set-include PRESET [--all-configured|--all-installed] [--grep NAME] [APPID|NAME...] [--dry-run] [--json]
                                    Set INCLUDE=presets/PRESET.env on many games
  --paths APPID|NAME [--json]         Shader cache, compatdata, install paths
  --init-unconfigured [--preset P] [--eac-only] [--dry-run]
  --prune-uninstalled [--dry-run] [--yes] [--json]
                                    Remove per-game .env for uninstalled games
  --export-config [--output PATH] [--include-local] [--no-profiles] [--include-tui] [--json]
                                    Pack launch.d + games configs (default: backup_dir from backup.conf)
  --backup-config [--output DIR|PATH] [--exclude-local] [--no-profiles] [--include-tui] [--json]
                                    Timestamped backup (default: backup_dir from backup.conf)
  --import-config ARCHIVE [--dry-run] [--yes] [--merge|--replace] [--exclude-local]
                          [--no-profiles] [--include-tui] [--json]
                                    Restore configs from export/backup tarball
  --restore-backup [ARCHIVE|DIR] [--dir PATH] [--list] [--appid APPID|NAME]
                   [--dry-run] [--yes] [--merge|--replace] [--exclude-local]
                   [--no-profiles] [--include-tui] [--json]
                                    Restore from latest or chosen backup archive
  --prune-backups [--dir PATH] [--keep N] [--dry-run] [--json]
                                    Remove oldest launchlayer-backup-*.tar.gz archives (keep=0: unlimited)
  --run-scheduled-backup [--dir PATH] [--keep N] [--json]
                                    Backup configs then prune per backup.conf (auto_prune, keep)
  --show-config APPID|NAME [--json]   Resolved config layers + launch chain
  --edit-appid APPID|NAME             Open/create per-game config in \$EDITOR
  --validate-config [APPID|all] [--json]  Lint .env files
  --suggest-config APPID|NAME [--apply]   Suggest optimizations using ProtonDB comments
  --scan-anticheat [--update-list]  Find EAC/BattlEye vs anticheat-appids.txt
  --scan-detections                 Audit native/anticheat/DLSS heuristic vs list mismatches (+ tips)

$(cli_bold "Community hub") $(cli_dim "(requires hub.conf — see share/launchlayer/templates/hub.conf.example)")
  --hub-fingerprint [--json] [--fingerprint-level minimal|standard|detailed]
                                    Machine fingerprint for similarity matching
  --hub-publish APPID|NAME [--note TEXT] [--config-id ID] [--all-configured] [--json]
                                    Upload or update per-game config(s) on LaunchLayer Hub
  --hub-update APPID|NAME|CONFIG_ID [--all-configured] [--note TEXT] [--include-new] [--json]
                                    Update existing shared config(s) for this machine
  --hub-delete CONFIG_ID [--yes] [--json]
                                    Delete a shared config (requires publish token)
  --hub-recommend APPID|NAME [--limit N] [--json]
                                    Configs from machines similar to yours
  --hub-search [--limit N] [--json] List machines most similar to this one
  --hub-apply CONFIG_ID [--history] [--dry-run] [--json]
                                    Download and apply a shared hub config (or historical version)
  --hub-history CONFIG_ID [--json]  List Community config publication history
  --hub-prefs [show|reset|set] [args...] [--json]
                                    Manage hub preferences (template: share/launchlayer/templates/hub.conf.example)
                                    User file: ~/.config/launchlayer/hub.conf

$(cli_bold "Runtime & diagnostics")
	--mcp [--privacy standard|redacted]
	                                  Run the read-only MCP stdio server (requires python3)
	--status [AppID|NAME] [--json]    Runtime state, shader/compatdata sizes
  --show-cpu-topology               V-Cache CCD hints for X3D_CPUS
  --cache-report [--min-gb N] [--grep NAME] [--json] [--shader-only|--compat-only]
  --launch-stats [APPID|NAME] [--json]  Summarize launch.log
  --dry-run %command%               Print env + chain without running
  --pause-vram-hogs / --resume-vram-hogs / --cleanup-stale-launch [pid]

$(cli_bold "Interactive")
  --tui                             Browse games, toggle settings, edit configs (fzf recommended)
  --tui-prefs [show|reset|set] [args...] [--json]
                                    Manage TUI preferences (template: share/launchlayer/templates/tui.conf.example)
                                    User file: ~/.config/launchlayer/tui.conf

$(cli_bold "General")
  --help, -h                        Show this help
  --version, -V                     Show version and paths

$(cli_bold "Config layers") $(cli_dim "(later overrides earlier)")
  launch.d/profiles/<profile>.env   LAUNCHLAYER_PROFILES or auto-detected
  launch.d/default.env              Global infrastructure defaults
  launch.d/local.env                Machine-local overrides (--write-local-config; gitignored; force-overwrites)
  launch.d/presets/*.env            Via INCLUDE= or auto standard/native (skipped when per-game file exists)
  games/<AppID>.env                 Per-game overrides (LAUNCHLAYER_GAMES_DIR)

$(cli_bold "Environment")
  LAUNCHLAYER_CONFIG_DIR           Override config root (launch.d parent)
  LAUNCHLAYER_GAMES_DIR            Per-game .env directory (default: ~/.local/share/launchlayer/games)
  LAUNCHLAYER_PROFILES           Comma-separated machine profiles
  NO_COLOR=1                        Disable ANSI colors in help output
  LAUNCHLAYER_QUIET=1              Same as --quiet (also suppresses launch warnings)

Global flags (before subcommands): --quiet|-q  --verbose|-v

Presets: standard, competitive, lightweight, native
EOF
}
