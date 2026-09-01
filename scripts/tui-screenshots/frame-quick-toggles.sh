#!/usr/bin/env bash
# shellcheck shell=bash
# frame-quick-toggles.sh — Per-game quick toggles for README screenshots.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap.sh
source "$SCRIPT_DIR/bootstrap.sh"
clear

appid=${1:-2357570}
if [[ "${LAUNCHLAYER_SCREENSHOT_FIXTURES:-}" == 1 ]]; then
	export LAUNCHLAYER_TUI_HEIGHT=65%
	name="Overwatch®"
else
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"
fi
tui_crumb_enter "Games"
tui_crumb_enter "$name"
tui_crumb_enter "Quick toggles"

options=()
if [[ "${LAUNCHLAYER_SCREENSHOT_FIXTURES:-}" == 1 ]]; then
	options=(
		"GAMEMODE  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"MANGOHUD  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"GAMESCOPE  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"GAMESCOPE_ADAPTIVE_SYNC  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"VRAM_HOGS  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"NETWORK_TUNE  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"PIPEWIRE_LOW_LATENCY  $(tui_glyph_bool_onoff 0 1)  $(cli_dim inherited)"
		"SHADER_CACHE_TRIM  $(tui_glyph_bool_onoff 0)  $(cli_dim override)"
		"GPU_POWER_CHECK  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
		"LAUNCH_WATCHDOG  $(tui_glyph_bool_onoff 1 1)  $(cli_dim inherited)"
	)
else
	prepare_launch_context "$appid"
	for key in "${TUI_TOGGLE_KEYS[@]}"; do
		options+=("$(tui_format_toggle_option "$appid" "$key")")
	done
fi
options+=(
	"Clear override (inherit from layers)"
	"Clear ALL overrides"
	Back
)

# shellcheck disable=SC2034 # Read by fzf_menu from bootstrap.sh.
TUI_MENU_CONTEXT=toggles
fzf_menu "$(tui_crumb_label "Flip per-game override")" "${options[@]}"
