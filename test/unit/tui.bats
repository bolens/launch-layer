#!/usr/bin/env bash
# Unit tests for lib/tui/primitives.sh helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "tui_fzf_footer_for includes help hint on menus" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s\n" "$(tui_fzf_footer_for menu)" "$(tui_fzf_footer_for game)" "$(tui_fzf_footer_for multi)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"? help"* ]]
	[[ "$output" == *"alt-s sort"* ]]
	[[ "$output" == *"ctrl-e editor"* ]]
	[[ "$output" == *"tab toggle"* ]]
}

@test "tui_fzf_sort_binds succeeds with set -e when default sorting stays enabled" {
	run bash -c '
		set -e
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		args=()
		tui_fzf_sort_binds args
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"alt-s:toggle-sort"* ]]
}

@test "tui fzf argument builders succeed with set -e for single-select menus" {
	run bash -c '
		set -e
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		menu_args=()
		game_args=()
		tui_fzf_build_args menu_args "Menu" menu
		tui_fzf_game_picker_args game_args "Pick a game" single
		printf "%s %s\n" "${#menu_args[@]}" "${#game_args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^[0-9]+\ [0-9]+$ ]]
}

@test "tui accessible mode uses a visible filter prompt and ASCII pointer" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" TUI_TEXT_STATUS=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		args=()
		tui_fzf_build_args args "Menu" menu
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"--prompt=Filter: "* ]]
	[[ "$output" == *"--pointer=>"* ]]
}

@test "tui_help_text covers main and game topics" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s\n" "$(tui_help_text main | head -1)" "$(tui_help_text game | head -1)" \
			"$(tui_help_text toggles | head -1)" "$(tui_help_text advanced | head -1)" \
			"$(tui_help_text menu | head -1)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Main menu"* ]]
	[[ "$output" == *"Game picker"* ]]
	[[ "$output" == *"Quick toggles"* ]]
	[[ "$output" == *"Advanced config"* ]]
	[[ "$output" == *"Navigation"* ]]
}

@test "tui_fzf_context_footer adds hub-specific status" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules hub
		launchlayer_source_tui
		tui_fzf_context_footer hub
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"hub:"* ]]
}

@test "tui_spinner_enabled respects TUI_SPINNER=0" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export TUI_SPINNER=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_spinner_enabled && echo enabled || echo disabled
	'
	[[ $status -eq 0 ]]
	[[ "$output" == disabled ]]
}

@test "tui_spinner_capture runs command and returns output" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export TUI_SPINNER=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		out="$(tui_spinner_capture "Testing…" printf "%s\n" hello)"
		echo "captured:$out"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "captured:hello" ]]
}

@test "tui_spinner_message_for maps known commands" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s\n" "$(tui_spinner_message_for init_unconfigured)" "$(tui_spinner_message_for show_doctor)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Initializing"* ]]
	[[ "$output" == *"health"* ]]
}

@test "tui_games_menu_item_label marks list-dependent rows while loading" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME
		XDG_CACHE_HOME="$(mktemp -d)"
		export TUI_SPINNER=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		printf "%s\n" "$(tui_games_menu_item_label "Browse & configure game")" \
			"$(tui_games_menu_item_label "Init unconfigured games")"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"loading"* ]]
	[[ "$output" == *"Init unconfigured games"* ]]
	[[ "$output" != *"Init unconfigured games  · loading"* ]]
}

@test "tui_games_cache_reconcile recovers stuck loading with persisted lines" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		tui_games_cache_paths
		mkdir -p "$TUI_GAMES_CACHE_DIR"
		printf "%s\n" "2357570 yes no yes listed unknown Overwatch" > "$TUI_GAMES_CACHE_FILE"
		printf "loading\n" > "$TUI_GAMES_CACHE_STATUS"
		printf "999999\n" > "$TUI_GAMES_CACHE_PID_FILE"
		tui_games_cache_reconcile
		echo "status:$(tui_games_cache_status)"
		tui_games_cache_ready && echo ready:yes || echo ready:no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"status:ready"* ]]
	[[ "$output" == *"ready:yes"* ]]
}

@test "tui_games_cache_reconcile discards orphaned lines.new when loader died" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		tui_games_cache_paths
		mkdir -p "$TUI_GAMES_CACHE_DIR"
		printf "%s\n" "2357570 yes no yes listed unknown Overwatch" > "${TUI_GAMES_CACHE_FILE}.new"
		printf "loading\n" > "$TUI_GAMES_CACHE_STATUS"
		printf "999999\n" > "$TUI_GAMES_CACHE_PID_FILE"
		tui_games_cache_reconcile
		echo "status:$(tui_games_cache_status)"
		[[ -f "${TUI_GAMES_CACHE_FILE}.new" ]] && echo new:present || echo new:absent
		tui_games_cache_has_lines && echo lines:yes || echo lines:no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"status:error"* ]]
	[[ "$output" == *"new:absent"* ]]
	[[ "$output" == *"lines:no"* ]]
}

@test "stale games cache loader cannot overwrite a newer loader owner" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME="$(mktemp -d)"
		fake_main="$(mktemp)"
		allow="$(mktemp)"
		rm -f "$allow"
		printf "#!/usr/bin/env bash\nwhile [[ ! -f %q ]]; do sleep 0.01; done\nprintf \\\"HEADER\\\\n42424242 yes no - unknown Game\\\\n\\\"\n" "$allow" > "$fake_main"
		chmod +x "$fake_main"
		export LAUNCHLAYER_MAIN_SCRIPT="$fake_main"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		tui_games_cache_spawn_loader
		old_pid="$(<"$TUI_GAMES_CACHE_PID_FILE")"
		printf "999999\n" > "$TUI_GAMES_CACHE_PID_FILE"
		touch "$allow"
		wait "$old_pid"
		[[ -f "$TUI_GAMES_CACHE_FILE" ]] && echo lines:present || echo lines:absent
		printf "owner=%s\n" "$(<"$TUI_GAMES_CACHE_PID_FILE")"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"lines:absent"* ]]
	[[ "$output" == *"owner=999999"* ]]
}

@test "tui_games_cache_apply_filter honors configured filter" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export TUI_GAME_FILTER=configured
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		printf "%s\n" "1 yes x" "2 no x" | tui_games_cache_apply_filter
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "1 yes x" ]]
	[[ "$output" != *"2 no"* ]]
}

@test "tui_games_cache_start survives set -u after purge" {
	run bash -c '
		set -u
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		tui_games_cache_start
		echo "dir:${TUI_GAMES_CACHE_DIR:-unset}"
		[[ -f "${TUI_GAMES_CACHE_STATUS:-}" ]] && echo status:present || echo status:absent
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"dir:"* ]]
	[[ "$output" != *"dir:unset"* ]]
	[[ "$output" == *"status:present"* ]]
}

@test "tui games menu dispatch hooks are wired" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		printf "%s\n" "$(handle_subcommand --tui-games-menu-reload)" "$(handle_subcommand --tui-games-menu-footer)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Browse & configure game"* ]]
	[[ "$output" == *"filter:"* ]]
}

@test "tui_games_menu_reload prints hub rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_games_cache_purge
		tui_games_menu_reload
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Browse & configure game"* ]]
}

@test "tui_game_list_column_header labels list-games columns" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_game_list_column_header
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *APPID* ]]
	[[ "$output" == *'*'* ]]
	[[ "$output" == *CFG* ]]
	[[ "$output" == *AC* ]]
	[[ "$output" == *ENGINE* ]]
}

@test "tui_game_picker_line_p rejects column header row" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		line="$(tui_game_list_column_header | tui_strip_ansi)"
		tui_game_picker_line_p "$line" && echo accepted || echo rejected
	'
	[[ $status -eq 0 ]]
	[[ "$output" == rejected ]]
}

@test "tui_format_game_picker_row aligns recent tag with header columns" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		sample="2357570    yes   no    listed   unknown      Overwatch"
		header="$(tui_game_list_column_header | tui_strip_ansi)"
		recent="$(tui_format_game_picker_row "$sample" 1 | tui_strip_ansi)"
		plain="$(tui_format_game_picker_row "$sample" | tui_strip_ansi)"
		echo "header-start:${header:0:1}"
		echo "recent-appid:${recent:2:7}"
		echo "plain-prefix:${plain:0:2}"
		echo "parsed:$(tui_parse_game_picker_line "$recent")"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"header-start:*"* ]]
	[[ "$output" == *"recent-appid:2357570"* ]]
	[[ "$output" == *'plain-prefix:  '* ]]
	[[ "$output" == *"parsed:2357570"* ]]
}

@test "tui_fzf_build_args binds home/end to list first/last" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_build_args args "Test header" menu
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"home:first"* ]]
	[[ "$output" == *"end:last"* ]]
	[[ "$output" == *"alt-s:toggle-sort"* ]]
	[[ "$output" != *"--no-sort"* ]]
}

@test "tui_fzf_build_args game picker defaults to no-sort with toggle" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_build_args args "Pick a game" game
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"alt-s:toggle-sort"* ]]
	[[ "$output" == *"--no-sort"* ]]
}

@test "tui_format_game_picker_row truncates long game names with ellipsis" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export TUI_GAME_PICKER_NAME_MAX=14
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		sample="1282150    yes   no    -        unreal       SpongeBob SquarePants: The Cosmic Shake"
		tui_format_game_picker_row "$sample" | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"SpongeBob Squ…"* ]]
	[[ "$output" != *"Cosmic Shake"* ]]
}

@test "tui-picker-appid dispatch parses row without grep" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		handle_subcommand --tui-picker-appid "  2357570    yes   no    listed   unknown      Overwatch"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "2357570" ]]
}

@test "tui_fzf_game_picker_args preview avoids grep for appid" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_game_picker_args args "Pick a game" single
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"--tui-game-preview-line"* ]]
	[[ "$output" != *"grep -oE"* ]]
}

@test "tui_game_picker_name_max fits list pane minus fixed columns" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export COLUMNS=120
		export LAUNCHLAYER_TUI_PREVIEW=right:35%:wrap
		unset TUI_GAME_PICKER_NAME_MAX TUI_GAME_PICKER_PREVIEW_PCT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_game_picker_name_max
	'
	[[ $status -eq 0 ]]
	# 120 cols - 35% preview - 3 chrome - 38 fixed prefix (2-col CFG/NAT glyphs) = 35
	[[ "$output" == "35" ]]
}

@test "tui_format_game_picker_row keeps short names on wide terminals" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export COLUMNS=160
		export LAUNCHLAYER_TUI_PREVIEW=right:35%:wrap
		unset TUI_GAME_PICKER_NAME_MAX TUI_GAME_PICKER_PREVIEW_PCT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		sample="2357570    yes   no    listed   unknown      Overwatch"
		tui_format_game_picker_row "$sample" | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Overwatch"* ]]
	[[ "$output" != *"…"* ]]
}

@test "tui_format_game_picker_row truncates only when name overflows list width" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export COLUMNS=90
		export LAUNCHLAYER_TUI_PREVIEW=right:35%:wrap
		unset TUI_GAME_PICKER_NAME_MAX TUI_GAME_PICKER_PREVIEW_PCT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		sample="1282150    yes   no    -        unreal       SpongeBob SquarePants: The Cosmic Shake"
		tui_format_game_picker_row "$sample" | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"…"* ]]
	[[ "$output" != *"Cosmic Shake"* ]]
}

@test "tui_parse_game_list_fields handles legacy EAC column rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		line="219990    yes   no    no    -        unknown      Grim Dawn"
		tui_parse_game_list_fields "$line"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'219990\tyes\tno\t-\tunknown\tGrim Dawn' ]]
}

@test "tui_games_cache_coalesce_lines merges wrapped game names" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		printf "%s\n" \
			"219990    yes   no    -        unknown      Grim" \
			"Dawn" \
		| tui_games_cache_coalesce_lines
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *219990* ]]
	[[ "$output" == *"Grim Dawn"* ]]
	[[ "$output" == *"unknown"* ]]
}

@test "tui_format_game_picker_row skips incomplete cache rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		tui_format_game_picker_row "219990"
		echo exit:$?
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "exit:0" ]]
	[[ "$output" != *219990* || "$output" == "exit:0" ]]
}

@test "tui_fzf_game_picker_args disables horizontal scroll for fixed columns" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_game_picker_args args "Pick a game" single
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"--scroll-off=1"* ]]
	[[ "$output" == *"--no-hscroll"* ]]
	[[ "$output" != *"--keep-right"* ]]
}

@test "tui_glyph_yesno maps yes/no to filled and open circles" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_glyph_yesno yes | tui_strip_ansi
		echo ---
		tui_glyph_yesno no | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"●"* ]]
	[[ "$output" == *"○"* ]]
}

@test "tui text status mode spells out state and aligns game columns" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" TUI_TEXT_STATUS=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s|%s|%s|%s\n" \
			"$(tui_glyph_yesno yes)" "$(tui_glyph_yesno no)" \
			"$(tui_glyph_doctor 2)" "$(tui_glyph_ac_type -)"
		line="2357570    yes   no    listed   unknown      Overwatch"
		tui_format_game_list_body "$line"
	'
	[[ $status -eq 0 ]]
	[[ "${lines[0]}" == "yes|no|2 issues|n/a" ]]
	[[ "${lines[1]}" == *"yes no"* ]]
	[[ "${lines[1]}" != *"●"* ]]
}

@test "tui game cache spinner becomes static when motion is disabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" TUI_SPINNER=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s" "$(tui_games_cache_spinner_frame)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "…" ]]
}

@test "tui_format_game_list_body uses glyphs for CFG and NAT" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		line="2357570    yes   no    listed   unknown      Overwatch"
		tui_format_game_list_body "$line" | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"●"* ]]
	[[ "$output" == *"○"* ]]
	[[ "$output" != *" yes "* ]]
}

@test "tui_glyph_ac_type renders dash as em dash" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_glyph_ac_type - | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "—" ]]
}

@test "tui_glyph_doctor shows warn glyph for open issues" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_glyph_doctor 0 | tui_strip_ansi
		echo ---
		tui_glyph_doctor 2 | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"●"* ]]
	[[ "$output" == *"⚠2"* ]]
}

@test "tui_fzf_build_args adds panel preview on main menu context" {
	command -v fzf >/dev/null 2>&1 || skip "fzf not installed"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$SCRIPT"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_build_args args "LaunchLayer" main
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"--tui-panel-preview"* ]]
	[[ "$output" != *"transform-preview"* ]]
}

@test "tui_fzf_build_args omits panel preview on game picker context" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$SCRIPT"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a args=()
		tui_fzf_game_picker_args args "Pick a game" single
		printf "%s\n" "${args[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"--tui-game-preview-line"* ]]
	[[ "$output" != *"--tui-panel"* ]]
}

@test "tui_panel_append_command stores command output for preview" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME TUI_SPINNER=0
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_panel_init
		tui_panel_append_command prune_uninstalled_configs $'"'"'=== Prune dry-run ===
orphan line'"'"'
		tui_panel_paths
		cat "$TUI_PANEL_ACTIVITY_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"orphan line"* ]]
	[[ "$output" != *"Scanning installed games"* ]]
}

@test "tui_menu_set_start_pos finds toggle key and label prefix rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_menu_set_start_pos GAMEMODE \
			"MANGOHUD ✓" \
			"GAMEMODE ✗  inherited" \
			"Back"
		printf "toggle:%s\n" "${TUI_FZF_START_POS:-missing}"
		unset TUI_FZF_START_POS
		tui_menu_set_start_pos "JSON view output:" \
			"Show current preferences" \
			"JSON view output: on" \
			"JSON view output: off"
		printf "label:%s\n" "${TUI_FZF_START_POS:-missing}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"toggle:2"* ]]
	[[ "$output" == *"label:2"* ]]
}

@test "tui_menu_set_start_pos empty anchor survives errexit" {
	run bash -c '
		set -euo pipefail
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_menu_set_start_pos "" "one" "two"
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "tui_fzf_pick honors TUI_FZF_START_POS bind" {
	command -v fzf >/dev/null 2>&1 || skip "fzf not installed"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		fzf() { printf '%s\n' "$@" >&2; printf 'two\n'; }
		export -f fzf
		TUI_FZF_START_POS=2
		export TUI_FZF_START_POS
		tui_fzf_pick Test menu one two three >/dev/null
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"start:pos(2)"* ]]
}

@test "tui_panel_render shows command output without section headers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME TUI_SPINNER=0 TUI_PANEL_ACTIVE=1
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules hub
		launchlayer_load_post_main
		launchlayer_source_tui
		load_backup_prefs 2>/dev/null || true
		tui_panel_init
		tui_panel_append_command show_doctor "doctor output line"
		tui_panel_render
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"doctor output line"* ]]
	[[ "$output" != *"=== Status ==="* ]]
	[[ "$output" != *"=== Recent output ==="* ]]
	[[ "$output" != *"filter:"* ]]
}

@test "tui_panel_append_text stores custom label and content" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_panel_init
		tui_panel_append_text "Publishing to hub…" $'"'"'upload ok'"'"'
		tui_panel_paths
		cat "$TUI_PANEL_ACTIVITY_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"upload ok"* ]]
	[[ "$output" != *"Publishing to hub"* ]]
}

@test "tui_run_capture routes output to panel when TUI_PANEL_ACTIVE" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME TUI_SPINNER=0 TUI_PANEL_ACTIVE=1
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_panel_active_p() { return 0; }
		export -f tui_panel_active_p
		tui_panel_init
		stdout="$(mktemp)"
		tui_run_capture "Publishing to hub…" printf "%s\n" capture-test-line >"$stdout"
		tui_panel_paths
		echo "stdout-bytes:$(wc -c <"$stdout" | tr -d "[:space:]")"
		cat "$TUI_PANEL_ACTIVITY_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"capture-test-line"* ]]
	[[ "$output" == *"stdout-bytes:0"* ]]
}

@test "tui_panel_note routes inline feedback without stdout when panel active" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME TUI_PANEL_ACTIVE=1
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_panel_active_p() { return 0; }
		export -f tui_panel_active_p
		tui_panel_init
		stdout="$(mktemp)"
		tui_panel_note "Set GAMEMODE=1" "Toggle" >"$stdout"
		tui_panel_paths
		echo "stdout-bytes:$(wc -c <"$stdout" | tr -d "[:space:]")"
		cat "$TUI_PANEL_ACTIVITY_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Set GAMEMODE=1"* ]]
	[[ "$output" == *"stdout-bytes:0"* ]]
}

@test "tui_show_text routes short messages to panel when TUI_PANEL_ACTIVE" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_CACHE_HOME TUI_PANEL_ACTIVE=1
		XDG_CACHE_HOME="$(mktemp -d)"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_panel_active_p() { return 0; }
		export -f tui_panel_active_p
		tui_panel_init
		stdout="$(mktemp)"
		tui_show_text "Saved settings" "Backup settings" >"$stdout"
		tui_panel_paths
		echo "stdout-bytes:$(wc -c <"$stdout" | tr -d "[:space:]")"
		cat "$TUI_PANEL_ACTIVITY_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Saved settings"* ]]
	[[ "$output" == *"stdout-bytes:0"* ]]
}

@test "tui_render_status_page shows grouped status rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules hub
		launchlayer_load_post_main
		launchlayer_source_tui
		load_backup_prefs 2>/dev/null || true
		tui_render_status_page
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"System status"* ]]
	[[ "$output" == *"Health"* ]]
	[[ "$output" == *"Doctor"* ]]
	[[ "$output" == *"Game filter"* ]]
	[[ "$output" != *"=== Recent output ==="* ]]
}

@test "tui_panel_preview_for_selection shows status page on Status row" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules hub
		launchlayer_load_post_main
		launchlayer_source_tui
		load_backup_prefs 2>/dev/null || true
		tui_panel_preview_for_selection Status | head -n 3
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"System status"* ]]
}

@test "tui_interface_settings_items groups compact preference rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a items=()
		tui_interface_settings_items items
		printf "%s\n" "${items[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"[Games] filter:"* ]]
	[[ "$output" == *"[UI] json"* ]]
	[[ "$output" == *"[fzf]"* ]]
	[[ "$output" == *"[·] Save and return"* ]]
}

@test "tui_backup_settings_items uses compact grouped rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a items=()
		tui_backup_settings_items items "~/backups"
		printf "%s\n" "${items[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"[Path] ~/backups"* ]]
	[[ "$output" == *"[Keep]"* ]]
	[[ "$output" == *"[Pack]"* ]]
	[[ "$output" == *"[Timer]"* ]]
	[[ "$output" == *"[·] Save"* ]]
	[[ "$output" != *"[Includes]"* ]]
}

@test "tui_hub_settings_items uses compact hub rows" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		declare -a items=()
		tui_hub_settings_items items "https://hub.example" "workstation" minimal
		printf "%s\n" "${items[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"[Hub] https://hub.example"* ]]
	[[ "$output" == *"[Auth] token"* ]]
	[[ "$output" == *"[Privacy] minimal"* ]]
}

@test "tui_menu_set_start_pos matches section anchor prefix" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_menu_set_start_pos "[Behavior] JSON view output:" \
			"[Behavior] JSON view output: x" "Back"
		echo "pos:${TUI_FZF_START_POS:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "pos:1" ]]
}

@test "TUI_TOGGLE_KEYS and TUI_ADVANCED_KEYS cover every config key" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		source_lib load-modules
		launchlayer_source_tui
		in_array() {
			local needle=$1; shift
			local x
			for x in "$@"; do
				[[ "$x" == "$needle" ]] && return 0
			done
			return 1
		}
		missing=0
		for key in "${LAUNCHLAYER_CONFIG_KEYS[@]}"; do
			if in_array "$key" "${TUI_TOGGLE_KEYS[@]}" || in_array "$key" "${TUI_ADVANCED_KEYS[@]}"; then
				continue
			fi
			echo "uncovered:$key"
			missing=1
		done
		# Dual-path keys must appear in both lists where intentional.
		in_array DLSS_SWAPPER "${TUI_TOGGLE_KEYS[@]}" || { echo missing-toggle:DLSS_SWAPPER; missing=1; }
		in_array DLSS_SWAPPER "${TUI_ADVANCED_KEYS[@]}" || { echo missing-advanced:DLSS_SWAPPER; missing=1; }
		# FWS alias lives in Advanced only; long name stays a toggle.
		in_array FLAWLESS_WIDESCREEN "${TUI_TOGGLE_KEYS[@]}" || { echo missing-toggle:FLAWLESS; missing=1; }
		in_array FWS "${TUI_ADVANCED_KEYS[@]}" || { echo missing-advanced:FWS; missing=1; }
		! in_array FWS "${TUI_TOGGLE_KEYS[@]}" || { echo fws-still-toggle; missing=1; }
		for key in FRAME_RATE OVERRIDE_PROTON SHADER_CACHE_BOOST_GB ENABLE_HDR GAMESCOPE_ADAPTIVE_SYNC; do
			in_array "$key" "${TUI_ADVANCED_KEYS[@]}" || {
				echo "missing-advanced:$key"
				missing=1
			}
		done
		(( missing == 0 )) && echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "tui_toggle_game_key cycles DLSS_SWAPPER through dll" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME
		XDG_DATA_HOME="$(mktemp -d)"
		export LAUNCHLAYER_GAMES_DIR="$XDG_DATA_HOME/games"
		mkdir -p "$LAUNCHLAYER_GAMES_DIR"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_load_post_main
		launchlayer_source_tui
		appid=424242
		printf "INCLUDE=presets/standard.env\n" > "$(tui_appid_env_path "$appid")"
		tui_toggle_game_key "$appid" DLSS_SWAPPER
		v1="$(tui_env_file_get "$(tui_appid_env_path "$appid")" DLSS_SWAPPER)"
		tui_toggle_game_key "$appid" DLSS_SWAPPER
		v2="$(tui_env_file_get "$(tui_appid_env_path "$appid")" DLSS_SWAPPER)"
		tui_toggle_game_key "$appid" DLSS_SWAPPER
		v3="$(tui_env_file_get "$(tui_appid_env_path "$appid")" DLSS_SWAPPER)"
		printf "v1=%s v2=%s v3=%s\n" "$v1" "$v2" "$v3"
		tui_bool_on dll && echo dll_on
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"v1=1"* ]]
	[[ "$output" == *"v2=dll"* ]]
	[[ "$output" == *"v3=0"* ]]
	[[ "$output" == *"dll_on"* ]]
}

@test "tui_pick_enum_key maps specialty and adaptive choices" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_menu() { printf "%s\n" "boxtron"; }
		tui_pick_enum_key SPECIALTY_RUNTIME
		tui_menu() { printf "%s\n" "(auto / empty)"; }
		out="$(tui_pick_enum_key GAMESCOPE_ADAPTIVE_SYNC)"; printf "vrr:[%s]\n" "$out"
		tui_menu() { printf "%s\n" "dll (presets only)"; }
		tui_pick_enum_key DLSS_SWAPPER
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"boxtron"* ]]
	[[ "$output" == *"vrr:[]"* ]]
	[[ "$output" == *"dll"* ]]
}

@test "tui_assist_only_key_p marks Depth3D and Geo11" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		tui_assist_only_key_p DEPTH3D && echo d3d
		tui_assist_only_key_p GEO11 && echo geo
		tui_assist_only_key_p GAMEMODE && echo bad || echo gamemode_ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"d3d"* ]]
	[[ "$output" == *"geo"* ]]
	[[ "$output" == *"gamemode_ok"* ]]
}

@test "TUI_TOGGLE_KEYS include DISABLE_STEAM_DECK" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		printf "%s\n" "${TUI_TOGGLE_KEYS[@]}" | grep -qx DISABLE_STEAM_DECK && echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "TUI_TOGGLE_KEYS include Arch latency flags" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		for key in LD_BIND_NOW VKBASALT LATENCYFLEX DISABLE_VBLANK; do
			printf "%s\n" "${TUI_TOGGLE_KEYS[@]}" | grep -qx "$key" || {
				echo "missing:$key"
				exit 1
			}
		done
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "TUI_TOGGLE_KEYS include upscaler and shader-boost flags" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		for key in DLSS_SWAPPER SHADER_CACHE_BOOST PROTON_DLSS_UPGRADE \
			PROTON_FSR4_UPGRADE PROTON_XESS_UPGRADE; do
			printf "%s\n" "${TUI_TOGGLE_KEYS[@]}" | grep -qx "$key" || {
				echo "missing:$key"
				exit 1
			}
		done
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "main menu Doctor prefix row matches Doctor* case pattern" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export NO_COLOR=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules
		launchlayer_source_tui
		row="Doctor $(tui_glyph_doctor 2 | tui_strip_ansi)"
		case "$row" in
			Doctor:*) echo "colon-only" ;;
			Doctor*) echo "matched" ;;
			*) echo "miss:$row" ;;
		esac
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "matched" ]]
}
