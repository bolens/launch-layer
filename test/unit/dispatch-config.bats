#!/usr/bin/env bash
# Unit tests for lib/commands/dispatch-config.sh routing.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

_dispatch_config_shell() {
	bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib commands cli
		'"$1"'
	'
}

@test "dispatch_config_subcommand scan-anticheat passes update-list flag" {
	run _dispatch_config_shell '
		source_lib platform config inspect
		scan_anticheat() { printf "scan:%s\n" "$1"; }
		dispatch_config_subcommand --scan-anticheat --update-list
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "scan:1" ]]
}

@test "dispatch_config_subcommand scan-detections routes to scan_detections" {
	run _dispatch_config_shell '
		source_lib platform config inspect steam
		scan_detections() { echo detections-called; }
		dispatch_config_subcommand --scan-detections
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "detections-called" ]]
}

@test "dispatch_config_subcommand init-unconfigured dry-run delegates args" {
	run _dispatch_config_shell '
		source_lib platform config inspect steam
		INIT_ARGS=()
		init_unconfigured() { INIT_ARGS=("$@"); echo "init:${*}"; }
		dispatch_config_subcommand --init-unconfigured --dry-run --eac-only
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"init: 1 1"* ]]
}

@test "dispatch_config_subcommand prune-uninstalled dry-run json delegates" {
	run _dispatch_config_shell '
		source_lib platform config inspect steam
		PRUNE_ARGS=()
		prune_uninstalled_configs() { PRUNE_ARGS=("$@"); echo "prune:${*}"; }
		dispatch_config_subcommand --prune-uninstalled --dry-run --json
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"prune:1 0 1"* ]]
}

@test "dispatch_config_subcommand validate-config routes target and json flag" {
	run _dispatch_config_shell '
		source_lib platform config inspect
		VALIDATE_ARGS=()
		validate_config() { VALIDATE_ARGS=("$@"); echo "validate:${*}"; }
		dispatch_config_subcommand --validate-config presets --json
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "validate:presets 1" ]]
}

@test "dispatch_config_subcommand write-local-config parses force and dry-run" {
	run _dispatch_config_shell '
		source_lib platform config detected-defaults
		WRITE_ARGS=()
		write_local_config() { WRITE_ARGS=("$@"); echo "write:${*}"; }
		dispatch_config_subcommand --write-local-config --force --dry-run
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "write:1 1" ]]
}

@test "dispatch_config_subcommand suggest-config delegates to suggest_config" {
	run _dispatch_config_shell '
		SUGGEST_ARGS=()
		suggest_config() { SUGGEST_ARGS=("$@"); echo "suggest:${*}"; }
		dispatch_config_subcommand --suggest-config 1091500 --apply
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "suggest:1091500 1" ]]
}

@test "suggest_config invokes protondb_suggest.py with apply flag" {
	run _dispatch_config_shell '
		source_lib platform config detected-defaults tools
		show_detect_environment() { echo "{\"gpu\":\"test\"}"; }
		command_required_or_fail() { return 0; }
		reset_config_state() { :; }
		load_launch_config() { :; }
		apply_defaults() { :; }
		python3() {
			echo "python3 called with: $*"
		}
		export -f python3
		suggest_config 1091500 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"python3 called with: "* ]]
	[[ "$output" == *"1091500"* ]]
	[[ "$output" == *"1"* ]]
}

@test "suggest_config respects per-game FORCE_PROTON during native detection" {
	run _dispatch_config_shell '
		source_lib platform config detected-defaults tools
		show_detect_environment() { echo "{\"gpu\":\"test\"}"; }
		command_required_or_fail() { return 0; }
		reset_config_state() { :; }
		load_launch_config() { FORCE_PROTON=1; }
		apply_defaults() { :; }
		detect_native_game() { [[ "${FORCE_PROTON:-0}" != 1 ]]; }
		python3() { printf "native=%s\n" "${!#}"; }
		export -f python3
		suggest_config 1091500 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"native=0"* ]]
}
