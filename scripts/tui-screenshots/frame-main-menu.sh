#!/usr/bin/env bash
# shellcheck shell=bash
# frame-main-menu.sh — Main TUI hub for README screenshots.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap.sh
source "$SCRIPT_DIR/bootstrap.sh"
clear

if [[ "${LAUNCHLAYER_SCREENSHOT_FIXTURES:-}" == 1 ]]; then
	export LAUNCHLAYER_TUI_HEIGHT=60%
	printf '%s\n' \
		"── filter: all │ doctor: $(tui_glyph_ok) │ vm: $(tui_glyph_ok)" \
		"── backup: $(tui_glyph_timer enabled) │ maint: $(tui_glyph_timer enabled) │ keep 7 │ hub: $(tui_glyph_ok) url · fp:standard"
else
	tui_print_status_banner
fi
export TUI_PANEL_ACTIVE=1
tui_panel_init

main_items=(
	Status
	Games
	"Config library"
	"Backup & restore"
	"Community hub"
	"System & tools"
	Settings
	Quit
)

# shellcheck disable=SC2034 # Read by fzf_menu from bootstrap.sh.
TUI_MENU_CONTEXT=main
fzf_menu "LaunchLayer ${LAUNCHLAYER_VERSION}" "${main_items[@]}"
