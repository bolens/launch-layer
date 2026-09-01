# shellcheck shell=bash
# lib/tui/pickers.sh — Game/preset pickers and bulk preset workflows.

[[ -n "${LAUNCHLAYER_TUI_PICKERS_LOADED:-}" ]] && return 0
LAUNCHLAYER_TUI_PICKERS_LOADED=1

# Width of the recent marker column prepended to picker rows (* = recent).
TUI_GAME_PICKER_RECENT_MARK='*'
TUI_GAME_PICKER_TAG_WIDTH=2
# Column body width before NAME (matches list_games printf layout; CFG/NAT use 2-col glyphs).
TUI_GAME_PICKER_BODY_PREFIX_WIDTH=38
TUI_GAME_PICKER_ELLIPSIS='…'
# Pointer, gutter, and list border columns subtracted from the list pane width.
TUI_GAME_PICKER_LIST_CHROME=3

# tui_truncate_ellipsis — Shorten text to max display chars, suffix with … when clipped.
tui_truncate_ellipsis() {
	local text=$1 max=${2:-32}
	(( max < 2 )) && max=2
	if ((${#text} <= max)); then
		printf '%s' "$text"
		return 0
	fi
	printf '%s%s' "${text:0:$((max - 1))}" "$TUI_GAME_PICKER_ELLIPSIS"
}

# tui_terminal_columns — Best-effort terminal width for picker layout.
tui_terminal_columns() {
	if [[ -n "${COLUMNS:-}" && "$COLUMNS" =~ ^[0-9]+$ ]]; then
		printf '%s' "$COLUMNS"
	elif command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
		tput cols
	else
		printf '%s' 80
	fi
}

# tui_game_picker_preview_pct — Share of terminal width used by the preview pane (0–100).
tui_game_picker_preview_pct() {
	if [[ -n "${TUI_GAME_PICKER_PREVIEW_PCT+x}" ]]; then
		printf '%s' "${TUI_GAME_PICKER_PREVIEW_PCT:-0}"
		return 0
	fi
	local preview="${LAUNCHLAYER_TUI_PREVIEW:-${LAUNCHLAYER_TUI_PREVIEW_DEFAULT:-right:35%:wrap}}"
	if [[ "$preview" =~ ^(up|down|hidden) ]]; then
		printf '%s' 0
		return 0
	fi
	if [[ "$preview" =~ :([0-9]+)% ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
		return 0
	fi
	printf '%s' 35
}

# tui_game_picker_list_width — Horizontal columns available to the game list pane.
tui_game_picker_list_width() {
	local cols pct preview preview_cols chrome=$TUI_GAME_PICKER_LIST_CHROME
	cols="$(tui_terminal_columns)"
	preview="${LAUNCHLAYER_TUI_PREVIEW:-${LAUNCHLAYER_TUI_PREVIEW_DEFAULT:-right:35%:wrap}}"
	if [[ "$preview" =~ ^(up|down|hidden) ]]; then
		printf '%s' $((cols - chrome))
		return 0
	fi
	if [[ -n "${TUI_GAME_PICKER_PREVIEW_PCT+x}" ]]; then
		pct="${TUI_GAME_PICKER_PREVIEW_PCT:-0}"
		printf '%s' $((cols - (cols * pct / 100) - chrome))
		return 0
	fi
	if [[ "$preview" =~ ^(left|right):([0-9]+)% ]]; then
		pct="${BASH_REMATCH[2]}"
		printf '%s' $((cols - (cols * pct / 100) - chrome))
		return 0
	fi
	if [[ "$preview" =~ ^(left|right):([0-9]+)(:|$) ]]; then
		preview_cols="${BASH_REMATCH[2]}"
		printf '%s' $((cols - preview_cols - chrome))
		return 0
	fi
	if [[ "$preview" =~ :([0-9]+)% ]]; then
		pct="${BASH_REMATCH[1]}"
		printf '%s' $((cols - (cols * pct / 100) - chrome))
		return 0
	fi
	printf '%s' $((cols - (cols * 35 / 100) - chrome))
}

# tui_game_picker_name_max — NAME chars before the row would exceed the list pane (0 = no limit).
tui_game_picker_name_max() {
	local list_w prefix max
	if [[ -n "${TUI_GAME_PICKER_NAME_MAX:-}" ]]; then
		printf '%s' "$TUI_GAME_PICKER_NAME_MAX"
		return 0
	fi
	# Without a real terminal width, do not preemptively truncate.
	if [[ -z "${COLUMNS:-}" ]] && { ! command -v tput >/dev/null 2>&1 || [[ ! -t 1 ]]; }; then
		printf '%s' 0
		return 0
	fi
	list_w="$(tui_game_picker_list_width)"
	prefix=$((TUI_GAME_PICKER_TAG_WIDTH + TUI_GAME_PICKER_BODY_PREFIX_WIDTH))
	tui_text_status_enabled && prefix=$((prefix + 2))
	max=$((list_w - prefix))
	(( max < 0 )) && max=0
	printf '%s' "$max"
}

# tui_truncate_game_name_if_needed — Ellipsis only when NAME would overflow the list pane.
tui_truncate_game_name_if_needed() {
	local name=$1 max=${2:-0}
	[[ -n "$name" ]] || return 0
	(( max < 1 )) && {
		printf '%s' "$name"
		return 0
	}
	if ((${#name} <= max)); then
		printf '%s' "$name"
		return 0
	fi
	tui_truncate_ellipsis "$name" "$max"
}

# tui_sanitize_game_list_line — Strip ANSI/CR and leading whitespace from a cache row.
tui_sanitize_game_list_line() {
	local line=$1
	line="$(printf '%s' "$line" | tui_strip_ansi | tr -d '\r')"
	line="${line#"${line%%[![:space:]]*}"}"
	printf '%s' "$line"
}

# tui_parse_game_list_fields — Parse a list_games row; prints tab-separated fields or returns 1.
tui_parse_game_list_fields() {
	local line=$1
	line="$(tui_sanitize_game_list_line "$line")"
	[[ -n "$line" ]] || return 1
	awk '{
		if ($1 !~ /^[0-9]+$/) exit 1
		appid = $1
		cfg = $2
		nat = $3
		if (cfg == "" || nat == "") exit 1
		if ($4 == "yes" || $4 == "no") {
			if (NF < 7) exit 1
			ac_type = $5
			engine = $6
			$1 = $2 = $3 = $4 = $5 = $6 = ""
		} else {
			if (NF < 6) exit 1
			ac_type = $4
			engine = $5
			$1 = $2 = $3 = $4 = $5 = ""
		}
		sub(/^ +/, "", $0)
		if (ac_type == "" || engine == "") exit 1
		printf "%s\t%s\t%s\t%s\t%s\t%s", appid, cfg, nat, ac_type, engine, $0
	}' <<< "$line"
}

# tui_games_cache_coalesce_lines — Merge wrapped name fragments; emit normalized list_games rows.
tui_games_cache_coalesce_lines() {
	local line buf=""
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="$(tui_sanitize_game_list_line "$line")"
		[[ -z "$line" ]] && continue
		if [[ "$line" =~ ^[0-9] ]]; then
			[[ -n "$buf" ]] && tui_emit_normalized_game_list_line "$buf"
			buf=$line
		else
			buf="${buf} ${line}"
		fi
	done
	[[ -n "$buf" ]] && tui_emit_normalized_game_list_line "$buf"
}

# tui_emit_normalized_game_list_line — Print one canonical list_games row or skip when incomplete.
tui_emit_normalized_game_list_line() {
	local line=$1
	local appid cfg nat ac_type engine name
	local parsed cfg_g nat_g ac_g bool_width
	parsed="$(tui_parse_game_list_fields "$line")" || return 0
	IFS=$'\t' read -r appid cfg nat ac_type engine name <<< "$parsed"
	cfg_g="$(tui_glyph_yesno "$cfg")"
	nat_g="$(tui_glyph_yesno "$nat")"
	ac_g="$(tui_glyph_ac_type "$ac_type")"
	bool_width="$(tui_game_bool_col_width)"
	printf '%-10s %-*s %-*s %-8s %-12s %s\n' \
		"$appid" "$bool_width" "$cfg_g" "$bool_width" "$nat_g" \
		"$ac_g" "$engine" "$name"
}

# tui_format_game_list_body — Align list_games fields; truncate NAME with … when needed.
tui_format_game_list_body() {
	local line=$1 name_max=${2:-}
	local appid cfg nat ac_type engine name parsed cfg_g nat_g ac_g bool_width
	if [[ -z "$name_max" ]]; then
		name_max="$(tui_game_picker_name_max)"
	fi
	parsed="$(tui_parse_game_list_fields "$line")" || return 1
	IFS=$'\t' read -r appid cfg nat ac_type engine name <<< "$parsed"
	cfg_g="$(tui_glyph_yesno "$cfg")"
	nat_g="$(tui_glyph_yesno "$nat")"
	ac_g="$(tui_glyph_ac_type "$ac_type")"
	bool_width="$(tui_game_bool_col_width)"
	name="$(tui_truncate_game_name_if_needed "$name" "$name_max")"
	printf '%-10s %-*s %-*s %-8s %-12s %s' \
		"$appid" "$bool_width" "$cfg_g" "$bool_width" "$nat_g" \
		"$ac_g" "$engine" "$name"
}

# tui_game_list_column_header — Column labels matching --list-games / picker rows.
tui_game_list_column_header() {
	local row bool_width
	bool_width="$(tui_game_bool_col_width)"
	row="$(printf '%-*s %-10s %-*s %-*s %-8s %-12s %s\n' \
		"$TUI_GAME_PICKER_TAG_WIDTH" "$TUI_GAME_PICKER_RECENT_MARK" \
		APPID "$bool_width" CFG "$bool_width" NAT \
		AC ENGINE NAME)"
	if cli_uses_color; then
		printf '%s\n' "$(cli_dim "$row")"
	else
		printf '%s\n' "$row"
	fi
}

# tui_format_game_picker_row — One aligned picker row; recent=1 marks launch.log recency.
tui_format_game_picker_row() {
	local line=$1 recent=${2:-0} name_max=${3:-}
	local formatted
	formatted="$(tui_format_game_list_body "$line" "$name_max")" || return 0
	if [[ "$recent" == 1 ]]; then
		printf '%-*s%s\n' "$TUI_GAME_PICKER_TAG_WIDTH" "$TUI_GAME_PICKER_RECENT_MARK" "$formatted"
	else
		printf '%-*s%s\n' "$TUI_GAME_PICKER_TAG_WIDTH" '' "$formatted"
	fi
}

# tui_game_picker_line_p — True when a picker row is a selectable game line.
tui_game_picker_line_p() {
	local line=$1 appid
	[[ -n "$line" ]] || return 1
	[[ "$line" != *"Loading installed games"* ]] || return 1
	[[ "$line" != *"Failed to load"* ]] || return 1
	[[ "$line" != *"loading installed games"* ]] || return 1
	appid="$(tui_parse_game_picker_line "$line")"
	[[ "$appid" =~ ^[0-9]+$ ]]
}

# tui_recent_game_appids — AppIDs from launch.log ordered by most recent play.
tui_recent_game_appids() {
	local limit=${1:-8}
	[[ -f "$LAUNCH_LOG_FILE" ]] || return 0
	tac "$LAUNCH_LOG_FILE" 2>/dev/null | awk -v limit="$limit" '
		function parse_line(    i) {
			appid = ""
			for (i = 2; i <= NF; i++) {
				if ($i ~ /^appid=/) {
					sub(/^appid=/, "", $i)
					appid = $i
				}
			}
		}
		{
			parse_line()
			if (appid == "" || appid == "unknown" || appid in seen) next
			seen[appid] = 1
			print appid
			if (++count >= limit) exit
		}
	'
}

# tui_build_game_picker_lines_from_cache — Recent-first picker rows using the warm cache.
tui_build_game_picker_lines_from_cache() {
	local -a all_lines=() recent_ids=() line appid
	local -A seen=()
	tui_game_list_column_header
	mapfile -t all_lines < <(tui_games_cache_lines)
	mapfile -t recent_ids < <(tui_recent_game_appids 8)
	for appid in "${recent_ids[@]}"; do
		for line in "${all_lines[@]}"; do
			[[ "${line%% *}" == "$appid" ]] || continue
			tui_format_game_picker_row "$line" 1
			seen["$appid"]=1
			break
		done
	done
	for line in "${all_lines[@]}"; do
		appid="${line%% *}"
		[[ -n "${seen[$appid]:-}" ]] && continue
		tui_format_game_picker_row "$line"
	done
}

# tui_build_game_picker_lines — Recent games first, then full library (deduped).
tui_build_game_picker_lines() {
	tui_games_cache_start
	if tui_games_cache_ready; then
		tui_build_game_picker_lines_from_cache
		return 0
	fi
	local -a all_lines=() recent_ids=() line appid
	local -A seen=()
	tui_game_list_column_header
	mapfile -t all_lines < <(tui_games_cache_wait && tui_games_cache_lines)
	mapfile -t recent_ids < <(tui_recent_game_appids 8)
	for appid in "${recent_ids[@]}"; do
		for line in "${all_lines[@]}"; do
			[[ "${line%% *}" == "$appid" ]] || continue
			tui_format_game_picker_row "$line" 1
			seen["$appid"]=1
			break
		done
	done
	for line in "${all_lines[@]}"; do
		appid="${line%% *}"
		[[ -n "${seen[$appid]:-}" ]] && continue
		tui_format_game_picker_row "$line"
	done
}

# tui_parse_game_picker_line — Extract AppID from a picker row (strips recent marker column).
tui_parse_game_picker_line() {
	local line=$1 appid
	[[ $# -gt 1 ]] && line="$*"
	line="$(printf '%s' "$line" | tui_strip_ansi)"
	line="${line:$TUI_GAME_PICKER_TAG_WIDTH}"
	line="${line#"${line%%[![:space:]]*}"}"
	read -r appid _ <<< "$line"
	printf '%s' "$appid"
}

# tui_render_game_preview_line — fzf preview for one picker row (no grep; safe when grep→rg).
tui_render_game_preview_line() {
	local line=$1 appid
	[[ $# -gt 1 ]] && line="$*"
	appid="$(tui_parse_game_picker_line "$line")"
	[[ "$appid" =~ ^[0-9]+$ ]] || return 1
	tui_render_game_preview "$appid"
}

# tui_list_games_lines — Game list rows for the picker, honoring TUI_GAME_FILTER.
tui_list_games_lines() {
	tui_games_cache_start
	if tui_games_cache_ready; then
		tui_games_cache_lines
		return 0
	fi
	tui_list_games_lines_core
}

# tui_games_picker_resize_reload — Replace picker list once when cache becomes ready.
tui_games_picker_resize_reload() {
	tui_games_cache_paths
	[[ -f "${TUI_GAMES_CACHE_DIR}/refresh-list" ]] || return 1
	rm -f "${TUI_GAMES_CACHE_DIR}/refresh-list"
	tui_games_picker_reload
}

# tui_games_picker_reload — fzf reload source for the async game picker.
tui_games_picker_reload() {
	tui_games_cache_start
	if tui_games_cache_has_lines; then
		tui_build_game_picker_lines_from_cache
	elif tui_games_cache_loading; then
		if cli_uses_color; then
			cli_dim '── Loading installed games… ──'
		else
			printf '%s\n' '── Loading installed games… ──'
		fi
	else
		printf '%s\n' 'Failed to load installed games.'
	fi
}

# tui_games_picker_header — fzf transform-header for async game picker.
tui_games_picker_header() {
	local base=${TUI_GAMES_FZF_HEADER_BASE:-Select a game}
	local frame
	if tui_games_cache_refreshing; then
		frame="$(tui_games_cache_spinner_frame)"
		if cli_uses_color; then
			printf '%s %s %s' "$base" "$(cli_cyan "$frame")" "$(cli_dim 'Refreshing game list…')"
		else
			printf '%s %s Refreshing game list…' "$base" "$frame"
		fi
		return 0
	fi
	if tui_games_cache_loading; then
		frame="$(tui_games_cache_spinner_frame)"
		if cli_uses_color; then
			printf '%s %s %s' "$base" "$(cli_cyan "$frame")" "$(cli_dim 'Loading installed games…')"
		else
			printf '%s %s Loading installed games…' "$base" "$frame"
		fi
		return 0
	fi
	printf '%s' "$base"
}

# tui_games_picker_footer — Footer for async game picker (spinner until ready).
tui_games_picker_footer() {
	local hint frame count
	hint="$(tui_fzf_footer_for game)"
	if tui_games_cache_busy; then
		count="$(tui_games_cache_count)"
		frame="$(tui_games_cache_spinner_frame)"
		if tui_games_cache_refreshing; then
			if cli_uses_color; then
				printf '%s │ %s %s · %s cached' \
					"$hint" "$(cli_cyan "$frame")" "$(cli_dim 'refreshing…')" "${count:-0}"
			else
				printf '%s │ %s refreshing… · %s cached' "$hint" "$frame" "${count:-0}"
			fi
		else
			if cli_uses_color; then
				printf '%s │ %s %s' "$hint" "$(cli_cyan "$frame")" "$(cli_dim 'loading games…')"
			else
				printf '%s │ %s loading games…' "$hint" "$frame"
			fi
		fi
		return 0
	fi
	count="$(tui_games_cache_count)"
	printf '%s │ filter:%s · %s games' "$hint" "${TUI_GAME_FILTER:-all}" "${count:-0}"
}

# tui_list_games_lines_core — Raw game list from --list-games (no spinner).
tui_list_games_lines_core() {
	local filter=${TUI_GAME_FILTER:-all}
	"$LAUNCHLAYER_MAIN_SCRIPT" --list-games 2>/dev/null | tail -n +2 | {
		if [[ "$filter" == configured ]]; then
			awk '$2 == "yes"'
		elif [[ "$filter" == unconfigured ]]; then
			awk '$2 == "no"'
		else
			cat
		fi
	}
}

# tui_pick_game_appid — Select an installed game; prints AppID.
tui_pick_game_appid() {
	local line appid header
	header="Select a game (filter=${TUI_GAME_FILTER:-all})"
	tui_games_cache_start
	if tui_has_fzf; then
		line="$(tui_fzf_game_picker_async "$header")" || return 1
	else
		local -a lines=() pick_lines=()
		mapfile -t lines < <(tui_build_game_picker_lines)
		((${#lines[@]} > 1)) || {
			tui_show_text "No games match filter: ${TUI_GAME_FILTER:-all}" "Games"
			return 1
		}
		pick_lines=("${lines[@]:1}")
		line="$(tui_select_pick "$header" "${pick_lines[@]}")" || return 1
	fi
	[[ "$line" != *"Loading installed games"* ]] || return 1
	tui_game_picker_line_p "$line" || return 1
	appid="$(tui_parse_game_picker_line "$line")"
	[[ "$appid" =~ ^[0-9]+$ ]] || return 1
	printf '%s\n' "$appid"
}

# tui_pick_preset — Choose a launch preset name.
tui_pick_preset() {
	local default=${TUI_DEFAULT_PRESET:-standard}
	tui_menu "Choose preset (default: $default)" "${TUI_PRESETS[@]}"
}

# tui_pick_enum_key — Menu picker for known enum-style advanced keys.
# Prints the value to set (may be empty). Returns 1 on cancel.
tui_pick_enum_key() {
	local key=$1 choice
	local -a opts=()
	case "$key" in
		DLSS_SWAPPER)
			opts=("0 (off)" "1 (NGX + presets)" "dll (presets only)")
			choice="$(tui_menu "DLSS_SWAPPER" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			case "$choice" in
				0*) printf '0' ;;
				1*) printf '1' ;;
				dll*) printf 'dll' ;;
				*) return 1 ;;
			esac
			;;
		SPECIALTY_RUNTIME)
			opts=("(clear)" "boxtron" "luxtorpeda" "roberta")
			choice="$(tui_menu "SPECIALTY_RUNTIME" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			[[ "$choice" == "(clear)" ]] && {
				printf ''
				return 0
			}
			printf '%s' "$choice"
			;;
		REPLAY_TOOL)
			opts=("auto" "gpu-screen-recorder" "replay-sorcery")
			choice="$(tui_menu "REPLAY_TOOL" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			printf '%s' "$choice"
			;;
		GAMESCOPE_FILTER)
			opts=("(clear)" "fsr" "nis" "linear" "nearest" "place")
			choice="$(tui_menu "GAMESCOPE_FILTER" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			[[ "$choice" == "(clear)" ]] && {
				printf ''
				return 0
			}
			printf '%s' "$choice"
			;;
		GAMESCOPE_ADAPTIVE_SYNC)
			opts=("(auto / empty)" "auto" "0 (force off)" "1 (force on)")
			choice="$(tui_menu "GAMESCOPE_ADAPTIVE_SYNC (VRR)" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			case "$choice" in
				"(auto / empty)") printf '' ;;
				auto) printf 'auto' ;;
				0*) printf '0' ;;
				1*) printf '1' ;;
				*) return 1 ;;
			esac
			;;
		GPU_SELECT)
			opts=("auto" "discrete" "nvidia" "amd" "intel")
			choice="$(tui_menu "GPU_SELECT" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			printf '%s' "$choice"
			;;
		OPTISCALER_PROXY)
			opts=("dxgi" "winmm" "version" "dbghelp" "d3d12" "wininet" "winhttp" "optiscaler" "OptiScaler.asi")
			choice="$(tui_menu "OPTISCALER_PROXY" "${opts[@]}" "Back")" || return 1
			[[ "$choice" == Back || -z "$choice" ]] && return 1
			printf '%s' "$choice"
			;;
		*)
			return 1
			;;
	esac
}

# tui_game_scope_count_configured — Count games with per-game configs.
tui_game_scope_count_configured() {
	"$LAUNCHLAYER_MAIN_SCRIPT" --list-games 2>/dev/null \
		| tail -n +2 | awk '$2 == "yes"' | wc -l
}

# tui_game_scope_count_filter — Count games matching the current picker filter.
tui_game_scope_count_filter() {
	tui_games_cache_start
	if tui_games_cache_ready; then
		tui_games_cache_count
		return 0
	fi
	tui_list_games_lines_core | wc -l | tr -d '[:space:]'
}

# tui_game_scope_count — Count games for bulk preset scopes.
tui_game_scope_count() {
	local mode=$1
	case "$mode" in
		filter)
			tui_spinner_capture "Counting games…" tui_game_scope_count_filter
			;;
		configured)
			tui_spinner_capture "Counting configured games…" tui_game_scope_count_configured
			;;
		*)
			printf '0\n'
			;;
	esac
}

# tui_collect_appids — Collect AppIDs for a bulk preset scope.
# Optional second arg: name substring for scope=grep.
tui_collect_appids() {
	local scope=$1 grep_pattern=${2:-} line appid -a appids=()
	case "$scope" in
		filter)
			while IFS= read -r line || [[ -n "$line" ]]; do
				appid="${line%% *}"
				[[ "$appid" =~ ^[0-9]+$ ]] && appids+=("$appid")
			done < <(tui_list_games_lines)
			;;
		configured)
			while IFS= read -r line || [[ -n "$line" ]]; do
				appid="${line%% *}"
				[[ "$appid" =~ ^[0-9]+$ ]] && appids+=("$appid")
			done < <("$LAUNCHLAYER_MAIN_SCRIPT" --list-games 2>/dev/null | tail -n +2 | awk '$2 == "yes"')
			;;
		grep)
			[[ -n "$grep_pattern" ]] || return 1
			while IFS= read -r line || [[ -n "$line" ]]; do
				appid="${line%% *}"
				[[ "$appid" =~ ^[0-9]+$ ]] && appids+=("$appid")
			done < <("$LAUNCHLAYER_MAIN_SCRIPT" --list-games --grep "$grep_pattern" 2>/dev/null | tail -n +2)
			;;
		multi)
			mapfile -t appids < <(tui_pick_game_appids_multi)
			;;
	esac
	((${#appids[@]})) || return 1
	printf '%s\n' "${appids[@]}"
}

# tui_pick_game_appids_multi — Fuzzy multi-select installed games; prints AppIDs.
tui_pick_game_appids_multi() {
	local -a lines=() selected=() line appid
	tui_has_fzf || {
		tui_show_text "Multi-select requires fzf$(tool_warn_suffix fzf)." "Games"
		return 1
	}
	mapfile -t lines < <(tui_build_game_picker_lines)
	((${#lines[@]} > 1)) || {
		tui_show_text "No games match filter: ${TUI_GAME_FILTER:-all}" "Games"
		return 1
	}
	mapfile -t selected < <(printf '%s\n' "${lines[@]}" | tui_fzf_run_stdin multi "Select games" game) || return 1
	((${#selected[@]})) || return 1
	for line in "${selected[@]}"; do
		tui_game_picker_line_p "$line" || continue
		appid="$(tui_parse_game_picker_line "$line")"
		[[ "$appid" =~ ^[0-9]+$ ]] && printf '%s\n' "$appid"
	done
}

# tui_bulk_preset_run — Preview or apply INCLUDE preset for collected AppIDs.
tui_bulk_preset_run() {
	local preset=$1
	shift
	local -a appids=("$@")
	local action

	((${#appids[@]})) || {
		tui_show_text "No games matched that scope." "Bulk preset"
		return 0
	}

	action="$(tui_menu "Bulk INCLUDE: $preset (${#appids[@]} games)" \
		"Preview (dry-run)" \
		"Apply" \
		"Back")" || return 0

	case "$action" in
		"Preview (dry-run)")
			tui_run_paged bulk_set_include_preset "$preset" --dry-run "${appids[@]}" || true
			;;
		"Apply")
			tui_confirm "Set INCLUDE=presets/${preset}.env on ${#appids[@]} game(s)?" || return 0
			tui_run_paged bulk_set_include_preset "$preset" "${appids[@]}" || true
			;;
		*) return 0 ;;
	esac
}

# tui_bulk_preset_menu — Apply INCLUDE preset to many games at once.
tui_bulk_preset_menu() {
	local action scope preset grep_pattern="" -a appids=()
	local filter_n configured_n

	filter_n="$(tui_game_scope_count filter)"
	configured_n="$(tui_game_scope_count configured)"

	action="$(tui_menu "Bulk INCLUDE preset" \
		"Current filter ($filter_n games)" \
		"All configured ($configured_n games)" \
		"Match name substring…" \
		"Pick games (multi-select)" \
		"Back")" || return 0

	case "$action" in
		"Current filter"*) scope="filter" ;;
		"All configured"*) scope="configured" ;;
		"Match name substring…"|"Match name substring...")
			scope="grep"
			read -r -p "Name substring: " grep_pattern </dev/tty || return 0
			[[ -n "$grep_pattern" ]] || return 0
			;;
		"Pick games (multi-select)")
			scope="multi"
			;;
		*) return 0 ;;
	esac

	case "$scope" in
		multi)
			mapfile -t appids < <(tui_collect_appids "$scope") || {
				tui_show_text "No games matched that scope." "Bulk preset"
				return 0
			}
			;;
		grep)
			mapfile -t appids < <(tui_spinner_capture "Collecting games…" tui_collect_appids grep "$grep_pattern") || {
				tui_show_text "No games matched: $grep_pattern" "Bulk preset"
				return 0
			}
			;;
		*)
			mapfile -t appids < <(tui_spinner_capture "Collecting games…" tui_collect_appids "$scope") || {
				tui_show_text "No games matched that scope." "Bulk preset"
				return 0
			}
			;;
	esac

	preset="$(tui_pick_preset)" || return 0
	tui_bulk_preset_run "$preset" "${appids[@]}"
}

# tui_games_cache_lines — Print normalized cache rows (legacy EAC column + wrapped names).
tui_games_cache_lines() {
	tui_games_cache_paths
	tui_games_cache_has_lines || return 1
	tui_games_cache_apply_filter <"$TUI_GAMES_CACHE_FILE" | tui_games_cache_coalesce_lines
}
