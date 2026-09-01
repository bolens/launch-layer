# shellcheck shell=bash
# scripts/tui-screenshots/bootstrap.sh — Load LaunchLayer modules for static TUI frames.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCREENSHOT_TMP="${TMPDIR:-/tmp}/launchlayer-tui-screenshots"
XDG_CACHE_HOME="$SCREENSHOT_TMP/cache"
XDG_CONFIG_HOME="$SCREENSHOT_TMP/config"
XDG_STATE_HOME="$SCREENSHOT_TMP/state"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
SCRIPT_DIR="$ROOT"
CONFIG_DIR="$ROOT"
LIB_DIR="$ROOT/lib"
LAUNCHLAYER_MAIN_SCRIPT="$ROOT/launchlayer"
export SCRIPT_DIR CONFIG_DIR LIB_DIR LAUNCHLAYER_MAIN_SCRIPT LAUNCHLAYER_CONFIG_DIR="$ROOT"
export XDG_CACHE_HOME XDG_CONFIG_HOME XDG_STATE_HOME

# shellcheck source=../../lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=../../lib/keys.sh
source "$LIB_DIR/keys.sh"
# shellcheck source=../../lib/load-modules.sh
source "$LIB_DIR/load-modules.sh"

launchlayer_load_pre_main
launchlayer_load_post_main

tui_load_config 2>/dev/null || true
load_backup_prefs 2>/dev/null || true
TUI_GAME_FILTER=${TUI_GAME_FILTER:-all}
TUI_PRESS_ENTER_LINES=${TUI_PRESS_ENTER_LINES:-8}

fzf_menu() {
	local header=$1
	shift
	local -a fzf_args=() context footer=""
	context="${TUI_MENU_CONTEXT:-menu}"
	if [[ "${LAUNCHLAYER_SCREENSHOT_FIXTURES:-}" == 1 ]]; then
		footer="$(tui_fzf_footer_for "$context")"
	else
		footer="$(tui_fzf_context_footer "$context")"
	fi
	tui_fzf_build_args fzf_args "$header" "$context" "$footer"
	if [[ "${LAUNCHLAYER_SCREENSHOT_FIXTURES:-}" == 1 && "$context" == main ]]; then
		fzf_args+=(
			--preview "cat $(printf '%q' "$ROOT/scripts/tui-screenshots/fixtures/main-status.txt")"
			--preview-window "$(tui_fzf_panel_window)"
		)
	fi
	printf '%s\n' "$@" | fzf "${fzf_args[@]}"
}
