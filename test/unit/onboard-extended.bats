#!/usr/bin/env bash
# Unit tests for lib/setup/onboard.sh extended setup flows.
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

@test "run_setup default runs completions and prints launch option" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export XDG_CONFIG_HOME="'"$SETUP_HOME"'"
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup completions
		detect_login_shell_name() { echo bash; }
		completions_enable() { echo "completions:bash"; }
		run_setup
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"completions:bash"* ]]
	[[ "$output" == *"Add to Steam Launch Options"* ]]
}

@test "run_setup write-local-config skips when local.env exists" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export XDG_CONFIG_HOME="'"$SETUP_HOME"'"
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		mkdir -p "'"$CONFIG_DIR"'/launch.d"
		printf "TEST=1\n" > "'"$CONFIG_DIR"'/launch.d/local.env"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup detected-defaults
		write_local_config() { echo write-called; }
		run_setup --write-local-config
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"local.env already exists"* ]]
	[[ "$output" != *"write-called"* ]]
}

@test "install_cli_symlink refuses to replace existing regular file" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export XDG_CONFIG_HOME="'"$SETUP_HOME"'"
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		mkdir -p "'"$SETUP_HOME"'/.local/bin"
		printf "not-a-symlink\n" > "'"$SETUP_HOME"'/.local/bin/launchlayer"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		install_cli_symlink 2>&1
	'
	[[ $status -eq 1 ]]
	[[ "$output" == *"Refusing to replace existing file"* ]]
}

@test "remove_legacy_cli_symlink ignores unrelated steaml symlink" {
	run bash -c '
		export HOME="'"$SETUP_HOME"'"
		export LAUNCHLAYER_MAIN_SCRIPT="'"$CONFIG_DIR"'/launchlayer"
		mkdir -p "'"$SETUP_HOME"'/.local/bin"
		ln -sfn /usr/bin/other-tool "'"$SETUP_HOME"'/.local/bin/steaml"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		remove_legacy_cli_symlink
		[[ -L "'"$SETUP_HOME"'/.local/bin/steaml" ]] && echo kept
	'
	[[ $status -eq 0 ]]
	[[ "$output" == kept ]]
	[[ "$output" != *"Removed legacy symlink"* ]]
}
