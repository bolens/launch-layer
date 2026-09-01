# shellcheck shell=bash
# lib/tui/fzf.sh — Shared fzf argument builders and selection helpers.

[[ -n "${LAUNCHLAYER_TUI_FZF_LOADED:-}" ]] && return 0
LAUNCHLAYER_TUI_FZF_LOADED=1

# tui_fzf_preview_window — Preview pane layout for game/action pickers.
tui_fzf_preview_window() {
	printf '%s' "${LAUNCHLAYER_TUI_PREVIEW:-${LAUNCHLAYER_TUI_PREVIEW_DEFAULT:-right:35%:wrap}}"
}

# tui_fzf_list_nav_binds — Home/End jump the list (fzf defaults move the query cursor).
# Optional suffix chains extra actions (e.g. async header/footer chrome refresh).
tui_fzf_list_nav_binds() {
	local -n out_arr=$1
	local suffix=${2:-}
	[[ -n "$suffix" ]] && suffix="+${suffix}"
	out_arr+=(
		--bind "home:first${suffix}"
		--bind "end:last${suffix}"
		--bind "page-up:page-up${suffix}"
		--bind "page-down:page-down${suffix}"
	)
}

# tui_fzf_sort_binds — Alt-S toggles fzf relevance sort vs stdin order (toggle-sort).
# Game/multi pickers default to --no-sort so recent-first rows stay grouped when filtering.
tui_fzf_sort_binds() {
	local -n out_arr=$1
	local suffix=${2:-} no_sort=${3:-0}
	[[ -n "$suffix" ]] && suffix="+${suffix}"
	out_arr+=(--bind "alt-s:toggle-sort${suffix}")
	[[ "$no_sort" == 1 ]] && out_arr+=(--no-sort)
	return 0
}

# tui_fzf_build_args — Shared fzf chrome: borders, footer hints, pointer, help bind.
tui_fzf_build_args() {
	local arr_name=$1
	local -n out_arr=$arr_name
	local header=$2 context=${3:-menu} footer=${4:-}
	local script_q
	out_arr=(
		--header="$header"
		--header-first
		--height="${LAUNCHLAYER_TUI_HEIGHT:-40%}"
		--border
		--list-border
		--layout=reverse
		--info=inline
		--cycle
		--pointer="$([[ "${TUI_TEXT_STATUS:-0}" == "1" ]] && printf '>' || printf '▶')"
		--prompt='Filter: '
	)
	if [[ -z "$footer" ]]; then
		footer="$(tui_fzf_context_footer "$context")"
	fi
	[[ -n "$footer" ]] && out_arr+=(--footer="$footer")
	if tui_has_fzf; then
		out_arr+=(--header-border --footer-border)
	fi
	if cli_uses_color; then
		out_arr+=(--ansi)
	fi
	out_arr+=(
		--bind "$(tui_fzf_help_bind "$context")"
	)
	tui_fzf_list_nav_binds "$arr_name"
	case "$context" in
		game|multi) tui_fzf_sort_binds "$arr_name" "" 1 ;;
		*) tui_fzf_sort_binds "$arr_name" ;;
	esac
	if [[ "$context" == actions && -n "${TUI_ACTION_APPID:-}" ]]; then
		script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
		out_arr+=(
			--preview "${script_q} --tui-game-preview ${TUI_ACTION_APPID} 2>/dev/null"
			--preview-window="$(tui_fzf_preview_window)"
			--bind "ctrl-d:execute(${script_q} --dry-run ${TUI_ACTION_APPID} 2>&1 | head -n 35)+abort"
		)
	fi
	if [[ -v TUI_FZF_EXTRA_BINDS && ${#TUI_FZF_EXTRA_BINDS[@]} -gt 0 ]]; then
		local bind
		for bind in "${TUI_FZF_EXTRA_BINDS[@]}"; do
			out_arr+=(--bind "$bind")
		done
	fi
	if tui_fzf_panel_context_p "$context" && tui_has_fzf; then
		script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
		case "$context" in
			status)
				out_arr+=(
					--preview "${script_q} --tui-status-page 2>/dev/null"
					--preview-window "$(tui_fzf_panel_window)"
				)
				;;
			main)
				out_arr+=(
					--preview "${script_q} --tui-panel-preview {} 2>/dev/null"
					--preview-window "$(tui_fzf_panel_window)"
				)
				;;
			*)
				out_arr+=(
					--preview "${script_q} --tui-panel 2>/dev/null"
					--preview-window "$(tui_fzf_panel_window)"
				)
				;;
		esac
	fi
	return 0
}

# tui_fzf_game_picker_args — Preview pane and editor/dry-run binds for game lists.
tui_fzf_game_picker_args() {
	local arr_name=$1
	local -n out_arr=$arr_name
	local header=$2 mode=${3:-single}
	local script_q context
	context="$([[ "$mode" == multi ]] && echo multi || echo game)"
	script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
	tui_fzf_build_args "$arr_name" "$header" "$context"
	if [[ "$context" == game || "$context" == multi ]]; then
		out_arr+=(
			--header-lines=1
			--scroll-off=1
			--no-hscroll
		)
		tui_has_fzf && out_arr+=(--header-lines-border=inline)
	fi
	if [[ "$mode" == multi ]]; then
		export TUI_GAME_PICKER_PREVIEW_PCT=0
	else
		unset TUI_GAME_PICKER_PREVIEW_PCT
	fi
	if [[ "$mode" != multi ]]; then
		out_arr+=(
			--preview "${script_q} --tui-game-preview-line {} 2>/dev/null"
			--preview-window="$(tui_fzf_preview_window)"
			--bind "ctrl-e:execute-silent(${script_q} --edit-appid \$(${script_q} --tui-picker-appid {}) < /dev/tty)+abort"
			--bind "ctrl-d:execute(${script_q} --dry-run \$(${script_q} --tui-picker-appid {}) 2>&1 | head -n 35)+abort"
		)
	fi
	[[ "$mode" == multi ]] && out_arr+=(--multi)
	return 0
}

# tui_fzf_run_stdin — Run fzf reading candidate lines from stdin.
tui_fzf_run_stdin() {
	local mode=$1 header=$2 context=$3
	local -a fzf_args=()
	if [[ "$context" == game ]]; then
		tui_fzf_game_picker_args fzf_args "$header" "$mode"
	else
		tui_fzf_build_args fzf_args "$header" "$context"
	fi
	fzf "${fzf_args[@]}"
}

# tui_fzf_games_async_poll_binds — Spinner in header/footer while loading; list reload only when ready.
tui_fzf_games_async_poll_binds() {
	local arr_name=$1
	local -n out_arr=$arr_name
	local reload_q=$2 resize_q=$3
	local header_q footer_q chrome
	tui_games_cache_chrome_bind_paths
	header_q="$TUI_GAMES_CACHE_CHROME_HEADER_BIND"
	footer_q="$TUI_GAMES_CACHE_CHROME_FOOTER_BIND"
	chrome="transform-footer:(${footer_q})+transform-header:(${header_q})"
	out_arr+=(
		--bind "start:reload(${reload_q})+${chrome}"
		--bind "load:${chrome}"
		--bind "resize:${chrome}+reload(${resize_q})"
		--bind "up:up+${chrome}"
		--bind "down:down+${chrome}"
	)
	tui_fzf_list_nav_binds "$arr_name" "$chrome"
}

# tui_fzf_games_hub_pick — Games hub menu with async list load (fzf reload + footer spinner).
tui_fzf_games_hub_pick() {
	local header=$1 result script_q reload_q resize_q init_header init_footer
	local -a fzf_args=()
	tui_games_cache_start
	TUI_GAMES_FZF_HEADER_BASE=$header
	export TUI_GAMES_FZF_HEADER_BASE
	TUI_GAMES_CACHE_CHROME_MODE=menu
	export TUI_GAMES_CACHE_CHROME_MODE
	tui_games_cache_write_chrome
	script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
	reload_q="${script_q} --tui-games-menu-reload"
	resize_q="${script_q} --tui-games-menu-resize-reload"
	init_header="$(cat "$TUI_GAMES_CACHE_CHROME_HEADER")"
	init_footer="$(cat "$TUI_GAMES_CACHE_CHROME_FOOTER")"
	tui_fzf_build_args fzf_args "$init_header" games "$init_footer"
	tui_fzf_games_async_poll_binds fzf_args "$reload_q" "$resize_q"
	tui_games_cache_watch_start "$$"
	result="$(tui_games_menu_print_items | fzf "${fzf_args[@]}")" || {
		tui_games_cache_watch_stop
		unset TUI_GAMES_FZF_HEADER_BASE TUI_GAMES_CACHE_CHROME_MODE
		return 1
	}
	tui_games_cache_watch_stop
	unset TUI_GAMES_FZF_HEADER_BASE TUI_GAMES_CACHE_CHROME_MODE
	[[ -n "$result" ]] || return 1
	case "$result" in
		*"loading installed games"*) return 1 ;;
	esac
	if tui_games_menu_item_loading_p "$result"; then
		tui_games_cache_wait || return 1
	fi
	tui_games_menu_normalize_selection "$result"
}

# tui_fzf_game_picker_async — Game picker that opens immediately and reloads when the cache is warm.
tui_fzf_game_picker_async() {
	local header=$1 result script_q reload_q resize_q init_header init_footer
	local -a fzf_args=()
	tui_games_cache_start
	TUI_GAMES_FZF_HEADER_BASE=$header
	export TUI_GAMES_FZF_HEADER_BASE
	TUI_GAMES_CACHE_CHROME_MODE=picker
	export TUI_GAMES_CACHE_CHROME_MODE
	export COLUMNS="${COLUMNS:-$(tput cols 2>/dev/null || true)}"
	tui_games_cache_write_chrome
	script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
	reload_q="${script_q} --tui-games-picker-reload"
	resize_q="${script_q} --tui-games-picker-resize-reload"
	init_header="$(cat "$TUI_GAMES_CACHE_CHROME_HEADER")"
	init_footer="$(cat "$TUI_GAMES_CACHE_CHROME_FOOTER")"
	tui_fzf_game_picker_args fzf_args "$init_header" single
	tui_fzf_games_async_poll_binds fzf_args "$reload_q" "$resize_q"
	tui_games_cache_watch_start "$$"
	result="$(printf '\n' | fzf "${fzf_args[@]}")" || {
		tui_games_cache_watch_stop
		unset TUI_GAMES_FZF_HEADER_BASE TUI_GAMES_CACHE_CHROME_MODE
		return 1
	}
	tui_games_cache_watch_stop
	unset TUI_GAMES_FZF_HEADER_BASE TUI_GAMES_CACHE_CHROME_MODE
	[[ -n "$result" ]] || return 1
	[[ "$result" != *"Loading installed games"* ]] || return 1
	tui_game_picker_line_p "$result" || return 1
	printf '%s\n' "$result"
}

# tui_fzf_pick — Fuzzy-select one line; returns 1 on cancel.
# Second arg sets footer context: menu, main, games, backup, hub, actions, toggles, confirm, game, multi.
# Set TUI_FZF_START_POS to a 1-based fzf row index to reopen on the same item (e.g. after toggling).
tui_fzf_pick() {
	local header=$1 context=${2:-menu}
	shift 2
	local result start_pos=${TUI_FZF_START_POS:-}
	local -a fzf_args=()
	[[ $# -gt 0 ]] || return 1
	tui_fzf_build_args fzf_args "$header" "$context"
	if [[ -n "$start_pos" && "$start_pos" =~ ^[0-9]+$ ]]; then
		fzf_args+=(--sync --bind "start:pos(${start_pos})" --bind "load:pos(${start_pos})")
	fi
	unset TUI_FZF_START_POS
	result="$(printf '%s\n' "$@" | fzf "${fzf_args[@]}")" || return 1
	[[ -n "$result" ]] || return 1
	printf '%s\n' "$result"
}

# tui_fzf_toggle_pick — Toggle menu: Enter flips booleans in-place; Back/Clear rows accept normally.
tui_fzf_toggle_pick() {
	local appid=$1 header=$2
	local script_q reload_q flip_q result start_pos=${TUI_FZF_START_POS:-}
	local -a fzf_args=()
	script_q="$(printf '%q' "$LAUNCHLAYER_MAIN_SCRIPT")"
	reload_q="${script_q} --tui-quick-toggles-reload $(printf '%q' "$appid")"
	flip_q="${script_q} --tui-quick-toggles-flip $(printf '%q' "$appid") {+f}"
	tui_fzf_build_args fzf_args "$(tui_crumb_label "$header")" toggles
	if [[ -n "$start_pos" && "$start_pos" =~ ^[0-9]+$ ]]; then
		fzf_args+=(--sync --bind "start:pos(${start_pos})" --bind "load:pos(${start_pos})")
	else
		fzf_args+=(--sync)
	fi
	unset TUI_FZF_START_POS
	fzf_args+=(
		--bind "enter:transform:[[ {+f} == Back || {+f} == Clear* ]] && echo accept || echo execute-silent(${flip_q})+reload(${reload_q})+pos(\$FZF_POS)"
	)
	result="$(tui_quick_toggles_reload "$appid" | fzf "${fzf_args[@]}")" || return 1
	[[ -n "$result" ]] || return 1
	printf '%s\n' "$result"
}
