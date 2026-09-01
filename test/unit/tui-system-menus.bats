#!/usr/bin/env bash
# Unit tests for lib/tui/menus-system-* helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
	export NO_COLOR=1
}

_tui_system_shell() {
	bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export NO_COLOR=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib load-modules completions
		launchlayer_source_tui
		_tui_menu_idx_file="$(mktemp)"
		echo 0 > "$_tui_menu_idx_file"
		tui_menu() {
			local idx choice
			idx="$(<"$_tui_menu_idx_file")"
			choice="${_tui_menu_queue[$idx]}"
			echo $((idx + 1)) > "$_tui_menu_idx_file"
			printf "%s\n" "$choice"
		}
		tui_menu_anchored() {
			shift 2
			tui_menu "$@"
		}
		'"$1"'
		rm -f "${_tui_menu_idx_file:-}"
	'
}

@test "tui_format_completion_shell_option shows enabled glyph" {
	run _tui_system_shell '
		completions_shell_status_brief() { echo enabled; }
		tui_format_completion_shell_option bash | tui_strip_ansi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"bash"* ]]
}

@test "tui_completion_shell_from_option extracts shell name" {
	run _tui_system_shell '
		tui_completion_shell_from_option "[Shell] bash ✓"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "bash" ]]
}

@test "tui_interface_settings_items includes games ui cache and fzf rows" {
	run _tui_system_shell '
		local -a items=()
		TUI_GAME_FILTER=all
		TUI_DEFAULT_PRESET=standard
		tui_interface_settings_items items
		printf "%s\n" "${items[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"[Games]"* ]]
	[[ "$output" == *"[UI]"* ]]
	[[ "$output" == *"[Cache]"* ]]
	[[ "$output" == *"[fzf]"* ]]
}

@test "tui_interface_games_menu updates picker filter" {
	run _tui_system_shell '
		_test_games_menu() {
			_tui_menu_queue=("Picker filter: all" "configured" "Back")
			TUI_GAME_FILTER=all
			tui_interface_games_menu
			printf "filter:%s\n" "${TUI_GAME_FILTER}"
		}
		_test_games_menu
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "filter:configured" ]]
}

@test "tui_interface_ui_menu toggles JSON output pref" {
	run _tui_system_shell '
		_test_ui_menu() {
			TUI_JSON_OUTPUT=0
			_tui_menu_queue=("JSON view output: ○" "Back")
			tui_interface_ui_menu
			printf "json:%s\n" "${TUI_JSON_OUTPUT}"
		}
		_test_ui_menu
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "json:1" ]]
}

@test "tui_interface_ui_menu toggles text labels and animation" {
	run _tui_system_shell '
		_test_accessibility_menu() {
			TUI_TEXT_STATUS=0
			TUI_SPINNER=1
			_tui_menu_queue=("Text status labels: ○" "Animated progress: on" "Back")
			tui_interface_ui_menu
			printf "text:%s spinner:%s\n" "$TUI_TEXT_STATUS" "$TUI_SPINNER"
		}
		_test_accessibility_menu
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "text:1 spinner:0" ]]
}

@test "tui_vram_menu pauses vram hogs on selection" {
	run _tui_system_shell '
		_test_vram_menu() {
			local paused=0
			_tui_menu_queue=("Pause VRAM hogs" "Back")
			pause_vram_hogs() { paused=1; }
			tui_show_text() { :; }
			tui_vram_menu
			printf "paused:%s\n" "$paused"
		}
		_test_vram_menu
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "paused:1" ]]
}

@test "tui_system_menu launch stats runs global launch_stats" {
	run _tui_system_shell '
		_test_system_stats() {
			tui_bats_menu_stub_install
			_tui_menu_queue=("Launch stats" "Back")
			tui_crumb_enter() { :; }
			tui_crumb_leave() { :; }
			tui_remember_main_menu() { :; }
			STATS_ARGS=()
			tui_run_paged() { STATS_ARGS=("$@"); return 0; }
			tui_system_menu
			printf "args:%s\n" "${STATS_ARGS[*]}"
			tui_bats_menu_stub_teardown
		}
		_test_system_stats
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"args:launch_stats"* ]]
}
