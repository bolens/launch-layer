# shellcheck shell=bash
# lib/tui/menus-system-settings.sh — Interface preferences (tui.conf).

[[ -n "${LAUNCHLAYER_TUI_SYSTEM_SETTINGS_LOADED:-}" ]] && return 0
LAUNCHLAYER_TUI_SYSTEM_SETTINGS_LOADED=1

# tui_interface_games_menu — Game picker filter and default preset.
tui_interface_games_menu() {
	local action val filter_label=${TUI_GAME_FILTER:-all}
	while true; do
		action="$(tui_menu "Games" \
			"Picker filter: ${filter_label}" \
			"Default init preset: ${TUI_DEFAULT_PRESET:-standard}" \
			"Back")" || return 0
		case "$action" in
			"Picker filter:"*)
				val="$(tui_menu "Game picker filter" "${TUI_GAME_FILTERS[@]}")" || continue
				TUI_GAME_FILTER=$val
				filter_label=$val
				;;
			"Default init preset:"*)
				val="$(tui_menu "Default preset" "${TUI_PRESETS[@]}")" || continue
				TUI_DEFAULT_PRESET=$val
				;;
			*) return 0 ;;
		esac
	done
}

# tui_interface_ui_menu — JSON, resume, and pause threshold.
tui_interface_ui_menu() {
	local action val last_anchor=""
	while true; do
		action="$(tui_menu_anchored "UI behavior" "$last_anchor" \
			"JSON view output: $(tui_glyph_pref "${TUI_JSON_OUTPUT:-0}")" \
			"Auto-resume last hub: $(tui_glyph_pref "${TUI_RESUME_LAST_MENU:-0}")" \
			"Text status labels: $(tui_glyph_pref "${TUI_TEXT_STATUS:-0}")" \
			"Animated progress: $(tui_glyph_pref "${TUI_SPINNER:-1}")" \
			"Press-enter threshold: ${TUI_PRESS_ENTER_LINES:-8}" \
			"Back")" || return 0
		case "$action" in
			"JSON view output:"*)
				last_anchor="JSON view output:"
				[[ "${TUI_JSON_OUTPUT:-0}" == "1" ]] && TUI_JSON_OUTPUT=0 || TUI_JSON_OUTPUT=1
				;;
			"Auto-resume last hub:"*)
				last_anchor="Auto-resume last hub:"
				[[ "${TUI_RESUME_LAST_MENU:-0}" == "1" ]] && TUI_RESUME_LAST_MENU=0 || TUI_RESUME_LAST_MENU=1
				;;
			"Text status labels:"*)
				last_anchor="Text status labels:"
				[[ "${TUI_TEXT_STATUS:-0}" == "1" ]] && TUI_TEXT_STATUS=0 || TUI_TEXT_STATUS=1
				;;
			"Animated progress:"*)
				last_anchor="Animated progress:"
				[[ "${TUI_SPINNER:-1}" == "1" ]] && TUI_SPINNER=0 || TUI_SPINNER=1
				;;
			"Press-enter threshold:"*)
				read -r -p "Lines before pause [${TUI_PRESS_ENTER_LINES:-8}]: " val </dev/tty || continue
				[[ -n "$val" && "$val" =~ ^[0-9]+$ ]] && TUI_PRESS_ENTER_LINES=$val
				;;
			*) return 0 ;;
		esac
	done
}

# tui_interface_fzf_menu — fzf height and preview layout.
tui_interface_fzf_menu() {
	local action val
	while true; do
		action="$(tui_menu "fzf layout" \
			"Height: ${LAUNCHLAYER_TUI_HEIGHT:-40%}" \
			"Preview: ${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}" \
			"Back")" || return 0
		case "$action" in
			"Height:"*)
				read -r -p "fzf height [${LAUNCHLAYER_TUI_HEIGHT:-40%}]: " val </dev/tty || continue
				[[ -n "$val" ]] && LAUNCHLAYER_TUI_HEIGHT=$val
				;;
			"Preview:"*)
				read -r -p "Preview window [${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}]: " val </dev/tty || continue
				[[ -n "$val" ]] && LAUNCHLAYER_TUI_PREVIEW=$val
				;;
			*) return 0 ;;
		esac
	done
}

# tui_interface_settings_items — Compact interface preference rows.
tui_interface_settings_items() {
	local arr_name=$1
	local -n out_arr=$arr_name
	local filter=${TUI_GAME_FILTER:-all} preset=${TUI_DEFAULT_PRESET:-standard}
	out_arr=(
		"[Games] filter: ${filter} · preset: ${preset}"
		"[UI] json $(tui_glyph_pref "${TUI_JSON_OUTPUT:-0}") · resume $(tui_glyph_pref "${TUI_RESUME_LAST_MENU:-0}") · text $(tui_glyph_pref "${TUI_TEXT_STATUS:-0}") · motion $(tui_glyph_pref "${TUI_SPINNER:-1}") · pause ${TUI_PRESS_ENTER_LINES:-8}"
		"[Cache] min ${TUI_CACHE_MIN_GB:-5} GB"
		"[fzf] $(tui_prefs_truncate "${LAUNCHLAYER_TUI_HEIGHT:-40%} · ${LAUNCHLAYER_TUI_PREVIEW:-${LAUNCHLAYER_TUI_PREVIEW_DEFAULT:-right:35%:wrap}}" 56)"
	)
	tui_prefs_footer "$arr_name" interface
}

# tui_interface_settings_menu — Edit tui.conf.
tui_interface_settings_menu() {
	local action val
	local -a items=()

	tui_crumb_enter "Interface"
	while true; do
		tui_interface_settings_items items
		action="$(tui_menu_anchored "tui.conf" "" "${items[@]}")" || return 0

		case "$action" in
			"[Games]"*)
				tui_interface_games_menu
				;;
			"[UI]"*)
				tui_interface_ui_menu
				;;
			"[Cache]"*)
				read -r -p "Min GB [${TUI_CACHE_MIN_GB:-5}]: " val </dev/tty || continue
				[[ -n "$val" ]] && TUI_CACHE_MIN_GB=$val
				;;
			"[fzf]"*)
				tui_interface_fzf_menu
				;;
			"[·] Show all")
				tui_run_paged show_tui_prefs "$(tui_json_flag)" || true
				;;
			"[·] Reset defaults")
				tui_confirm "Reset interface settings to repo defaults?" || continue
				reset_tui_prefs || continue
				;;
			"[·] Save and return")
				tui_save_config
				tui_crumb_leave
				return 0
				;;
			"Back without saving"|*)
				tui_crumb_leave
				return 0
				;;
		esac
	done
}

# tui_cache_report — Cache audit using TUI min-GB preference.
tui_cache_report() {
	local min_gb=${1:-${TUI_CACHE_MIN_GB:-5}} mode=${2:-both} grep_pattern=${3:-}
	[[ "$min_gb" =~ ^[0-9]+$ ]] || min_gb=5
	cache_report "$min_gb" "$mode" "$grep_pattern" 0
}

# tui_cache_report_menu — Cache audit with CLI-parity filters.
tui_cache_report_menu() {
	local action val min_gb mode grep_pattern
	min_gb=${TUI_CACHE_MIN_GB:-5}
	while true; do
		action="$(tui_menu "Cache report (min ${min_gb} GB)" \
			"Full report (shader + compatdata)" \
			"Shader cache only" \
			"Compatdata only" \
			"Filter by game name (--grep)" \
			"Change min GB threshold" \
			"Back")" || return 0

		case "$action" in
			"Full report (shader + compatdata)")
				tui_run_paged tui_cache_report "$min_gb" both "" || true
				;;
			"Shader cache only")
				tui_run_paged tui_cache_report "$min_gb" shader "" || true
				;;
			"Compatdata only")
				tui_run_paged tui_cache_report "$min_gb" compat "" || true
				;;
			"Filter by game name (--grep)")
				read -r -p "Name substring: " grep_pattern </dev/tty || continue
				[[ -n "$grep_pattern" ]] || continue
				tui_run_paged tui_cache_report "$min_gb" both "$grep_pattern" || true
				;;
			"Change min GB threshold")
				read -r -p "Min GB [${min_gb}]: " val </dev/tty || continue
				[[ -n "$val" && "$val" =~ ^[0-9]+$ ]] && min_gb=$val
				;;
			*) return 0 ;;
		esac
	done
}
