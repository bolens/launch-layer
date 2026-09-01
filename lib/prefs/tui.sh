# shellcheck shell=bash
# lib/prefs/tui.sh — TUI preferences and --tui-prefs helpers.

LAUNCHLAYER_TUI_PREVIEW_DEFAULT='right:35%:wrap'

# _tui_prefs_set_defaults — Initialize TUI preference globals.
_tui_prefs_set_defaults() {
	TUI_GAME_FILTER=${TUI_GAME_FILTER:-all}
	TUI_CACHE_MIN_GB=${TUI_CACHE_MIN_GB:-5}
	TUI_DEFAULT_PRESET=${TUI_DEFAULT_PRESET:-standard}
	TUI_LAST_MENU=${TUI_LAST_MENU:-}
	TUI_JSON_OUTPUT=${TUI_JSON_OUTPUT:-0}
	TUI_RESUME_LAST_MENU=${TUI_RESUME_LAST_MENU:-0}
	TUI_TEXT_STATUS=${TUI_TEXT_STATUS:-0}
	TUI_SPINNER=${TUI_SPINNER:-1}
	TUI_PRESS_ENTER_LINES=${TUI_PRESS_ENTER_LINES:-8}
	export LAUNCHLAYER_TUI_HEIGHT="${LAUNCHLAYER_TUI_HEIGHT:-40%}"
	export LAUNCHLAYER_TUI_PREVIEW="${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}"
}

# _tui_prefs_parse_file — Parse tui.conf lines into TUI globals.
_tui_prefs_parse_file() {
	local file=$1
	local line key val
	[[ -f "$file" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" == *=* ]] || continue
		key="${line%%=*}"
		key="${key#"${key%%[![:space:]]*}"}"
		val="${line#*=}"
		case "$key" in
			game_filter) TUI_GAME_FILTER=$val ;;
			cache_min_gb) TUI_CACHE_MIN_GB=$val ;;
			default_preset) TUI_DEFAULT_PRESET=$val ;;
			last_menu) TUI_LAST_MENU=$val ;;
			json_output) TUI_JSON_OUTPUT=$val ;;
			resume_last_menu) TUI_RESUME_LAST_MENU=$val ;;
			text_status) TUI_TEXT_STATUS=$val ;;
			spinner) TUI_SPINNER=$val ;;
			press_enter_lines) TUI_PRESS_ENTER_LINES=$val ;;
			fzf_height) LAUNCHLAYER_TUI_HEIGHT=$val ;;
			fzf_preview) LAUNCHLAYER_TUI_PREVIEW=$val ;;
		esac
	done < "$file"
	return 0
}

# tui_load_config — Load saved TUI preferences (safe defaults when missing).
tui_load_config() {
	_tui_prefs_set_defaults
	_tui_prefs_parse_file "$(tui_config_path)" || \
		_tui_prefs_parse_file "$(tui_config_example_path)" || true
	return 0
}

# _tui_write_config_file — Write tui.conf; quiet=1 skips the confirmation line.
_tui_write_config_file() {
	local quiet=$1 file dir example
	_tui_prefs_set_defaults
	file="$(tui_config_path)"
	dir="$(dirname "$file")"
	example="$(tui_config_example_path)"
	mkdir -p "$dir"
	{
		echo "# LaunchLayer TUI preferences"
		[[ -f "$example" ]] && echo "# Defaults: $example"
		cat <<EOF
game_filter=${TUI_GAME_FILTER:-all}
cache_min_gb=${TUI_CACHE_MIN_GB:-5}
default_preset=${TUI_DEFAULT_PRESET:-standard}
last_menu=${TUI_LAST_MENU:-}
json_output=${TUI_JSON_OUTPUT:-0}
resume_last_menu=${TUI_RESUME_LAST_MENU:-0}
text_status=${TUI_TEXT_STATUS:-0}
spinner=${TUI_SPINNER:-1}
press_enter_lines=${TUI_PRESS_ENTER_LINES:-8}
fzf_height=${LAUNCHLAYER_TUI_HEIGHT:-40%}
fzf_preview=${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}
EOF
	} > "$file"
	if (( ! quiet )); then
		if declare -f tui_panel_note >/dev/null 2>&1; then
			tui_panel_note "Saved TUI settings to $file" "TUI settings"
		else
			echo "Saved TUI settings to $file"
		fi
	fi
}

# tui_save_config — Persist TUI preferences.
tui_save_config() {
	_tui_write_config_file 0
}

# tui_save_config_quiet — Persist TUI preferences without printing confirmation.
tui_save_config_quiet() {
	_tui_write_config_file 1
}

# reset_tui_prefs — Restore tui.conf from the repo example template.
reset_tui_prefs() {
	local example user_file
	example="$(tui_config_example_path)"
	user_file="$(tui_config_path)"
	if [[ ! -f "$example" ]]; then
		echo "Missing TUI template: $example" >&2
		return 1
	fi
	mkdir -p "$(dirname "$user_file")"
	cp "$example" "$user_file"
	tui_load_config
	if declare -f tui_panel_note >/dev/null 2>&1; then
		tui_panel_note "Reset TUI preferences to defaults ($user_file)" "TUI settings"
	else
		echo "Reset TUI preferences to defaults ($user_file)"
	fi
}

# show_tui_prefs — Print current TUI preferences.
show_tui_prefs() {
	local json=${1:-0}
	tui_load_config
	if [[ "$json" == "1" ]]; then
		printf '{"path":%s,"example":%s,"game_filter":%s,"cache_min_gb":%s,"default_preset":%s,"last_menu":%s,"json_output":%s,"resume_last_menu":%s,"text_status":%s,"spinner":%s,"press_enter_lines":%s,"fzf_height":%s,"fzf_preview":%s}\n' \
			"$(json_string "$(tui_config_path)")" \
			"$(json_string "$(tui_config_example_path)")" \
			"$(json_string "${TUI_GAME_FILTER:-all}")" \
			"${TUI_CACHE_MIN_GB:-5}" \
			"$(json_string "${TUI_DEFAULT_PRESET:-standard}")" \
			"$(json_string "${TUI_LAST_MENU:-}")" \
			"${TUI_JSON_OUTPUT:-0}" \
			"${TUI_RESUME_LAST_MENU:-0}" \
			"${TUI_TEXT_STATUS:-0}" \
			"${TUI_SPINNER:-1}" \
			"${TUI_PRESS_ENTER_LINES:-8}" \
			"$(json_string "${LAUNCHLAYER_TUI_HEIGHT:-40%}")" \
			"$(json_string "${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}")"
		return 0
	fi
	echo "=== TUI preferences ==="
	echo "path=$(tui_config_path)"
	echo "example=$(tui_config_example_path)"
	echo "game_filter=${TUI_GAME_FILTER:-all}"
	echo "cache_min_gb=${TUI_CACHE_MIN_GB:-5}"
	echo "default_preset=${TUI_DEFAULT_PRESET:-standard}"
	echo "last_menu=${TUI_LAST_MENU:-}"
	echo "json_output=${TUI_JSON_OUTPUT:-0}"
	echo "resume_last_menu=${TUI_RESUME_LAST_MENU:-0}"
	echo "text_status=${TUI_TEXT_STATUS:-0}"
	echo "spinner=${TUI_SPINNER:-1}"
	echo "press_enter_lines=${TUI_PRESS_ENTER_LINES:-8}"
	echo "fzf_height=${LAUNCHLAYER_TUI_HEIGHT:-40%}"
	echo "fzf_preview=${LAUNCHLAYER_TUI_PREVIEW:-$LAUNCHLAYER_TUI_PREVIEW_DEFAULT}"
}

# handle_tui_prefs_subcommand — Manage tui.conf (show, reset, set).
handle_tui_prefs_subcommand() {
	local action=${1:-show} json=0
	shift || true
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--json) json=1; shift ;;
			*) break ;;
		esac
	done
	tui_load_config
	case "$action" in
		show)
			show_tui_prefs "$json"
			;;
		reset)
			reset_tui_prefs || return $?
			;;
		set)
			local key=${1:-} val=${2:-}
			[[ -n "$key" && -n "$val" ]] || {
				echo "Usage: $0 --tui-prefs set KEY VALUE" >&2
				echo "Keys: game_filter, cache_min_gb, default_preset, last_menu, json_output, resume_last_menu, text_status, spinner, press_enter_lines, fzf_height, fzf_preview" >&2
				return 1
			}
			case "$key" in
				game_filter) TUI_GAME_FILTER=$val ;;
				cache_min_gb) TUI_CACHE_MIN_GB=$val ;;
				default_preset) TUI_DEFAULT_PRESET=$val ;;
				last_menu) TUI_LAST_MENU=$val ;;
				json_output) TUI_JSON_OUTPUT=$val ;;
				resume_last_menu) TUI_RESUME_LAST_MENU=$val ;;
				text_status) TUI_TEXT_STATUS=$val ;;
				spinner) TUI_SPINNER=$val ;;
				press_enter_lines) TUI_PRESS_ENTER_LINES=$val ;;
				fzf_height) LAUNCHLAYER_TUI_HEIGHT=$val ;;
				fzf_preview) LAUNCHLAYER_TUI_PREVIEW=$val ;;
				*)
					echo "Unknown TUI preference key: $key" >&2
					return 1
					;;
			esac
			tui_save_config
			;;
		*)
			echo "Usage: $0 --tui-prefs {show|reset|set} [args...] [--json]" >&2
			return 1
			;;
	esac
}
