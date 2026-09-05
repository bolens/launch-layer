#!/usr/bin/env bash
# Unit tests for lib/setup/onboard.sh helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
	SETUP_HOME="$(mktemp -d)"
	export CONFIG_DIR="$SETUP_HOME/config"
	mkdir -p "$CONFIG_DIR/launch.d"
	export HOME="$SETUP_HOME"
	export XDG_CONFIG_HOME="$SETUP_HOME"
}

teardown() {
	[[ -n "${SETUP_HOME:-}" ]] && rm -rf "$SETUP_HOME"
}

@test "print_steam_launch_option wraps script and percent command" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT=/opt/launchlayer/launchlayer
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		print_steam_launch_option
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"/opt/launchlayer/launchlayer" %command%'* ]]
}

@test "install_cli_symlink creates launchlayer link in local bin" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export XDG_CONFIG_HOME="'"$SETUP_HOME"'"
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		touch "$LAUNCHLAYER_MAIN_SCRIPT"
		chmod +x "$LAUNCHLAYER_MAIN_SCRIPT"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		install_cli_symlink
		readlink "'"$SETUP_HOME"'/.local/bin/launchlayer"
	'
	[[ $status -eq 0 ]]
	[[ -L "$SETUP_HOME/.local/bin/launchlayer" ]]
	[[ "$(readlink "$SETUP_HOME/.local/bin/launchlayer")" == "$CONFIG_DIR/launchlayer" ]]
}

@test "remove_legacy_cli_symlink drops owned steaml symlink" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		mkdir -p "'"$SETUP_HOME"'/.local/bin"
		ln -sfn "$LAUNCHLAYER_MAIN_SCRIPT" "'"$SETUP_HOME"'/.local/bin/steaml"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		remove_legacy_cli_symlink
		[[ ! -L "'"$SETUP_HOME"'/.local/bin/steaml" ]] && echo removed
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Removed legacy symlink"* ]]
	[[ "$output" == *"removed"* ]]
}

@test "run_setup --symlink only installs cli link" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export XDG_CONFIG_HOME="'"$SETUP_HOME"'"
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		touch "$LAUNCHLAYER_MAIN_SCRIPT"
		chmod +x "$LAUNCHLAYER_MAIN_SCRIPT"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup completions
		completions_enable() { echo "completions-skipped"; }
		run_setup --symlink
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Linked"* ]]
	[[ "$output" != *"completions-skipped"* ]]
	[[ -L "$SETUP_HOME/.local/bin/launchlayer" ]]
}

@test "run_setup rejects unknown flag" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		run_setup --not-a-setup-flag 2>&1
	'
	[[ $status -eq 1 ]]
	[[ "$output" == *"Usage:"* ]]
}
