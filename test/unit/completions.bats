#!/usr/bin/env bash
# Unit tests for lib/completions/helpers.sh.
load '../helpers.bash'

setup() {
	bats_unit_setup
	source_lib completions
}

@test "normalize_completions_shell maps aliases" {
	[[ "$(normalize_completions_shell osh)" == bash ]]
	[[ "$(normalize_completions_shell pwsh)" == pwsh ]]
	[[ "$(normalize_completions_shell powershell)" == pwsh ]]
	[[ "$(normalize_completions_shell nu)" == nu ]]
	[[ "$(normalize_completions_shell nushell)" == nu ]]
	[[ "$(normalize_completions_shell fish)" == fish ]]
}

@test "normalize_completions_shell returns unknown shells unchanged" {
	[[ "$(normalize_completions_shell bash)" == bash ]]
	[[ "$(normalize_completions_shell zsh)" == zsh ]]
}

@test "completions_shell_status_brief reports disabled for unknown shell" {
	run completions_shell_status_brief not-a-shell
	[[ $status -eq 1 ]]
	[[ "$output" == unknown ]]
}

@test "concurrent completion manifest updates preserve both keys" {
	command -v flock >/dev/null 2>&1 || skip "flock is not installed"
	local state_dir="$BATS_TEST_TMPDIR/config"
	run env XDG_CONFIG_HOME="$state_dir" bash -c '
		set -euo pipefail
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib completions
		update_manifest_key BASH_METHOD bash &
		first=$!
		update_manifest_key ZSH_METHOD zsh &
		second=$!
		wait "$first" "$second"
		sort "$(completions_manifest_file)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'BASH_METHOD=bash\nZSH_METHOD=zsh' ]]
}

@test "concurrent profile installs append one managed block" {
	command -v flock >/dev/null 2>&1 || skip "flock is not installed"
	local profile="$BATS_TEST_TMPDIR/profile"
	run bash -c '
		set -euo pipefail
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib completions
		profile_append_completions_block "'"$profile"'" /tmp/launchlayer.bash &
		first=$!
		profile_append_completions_block "'"$profile"'" /tmp/launchlayer.bash &
		second=$!
		wait "$first" "$second"
		grep -cF "$COMPLETIONS_MARKER_BEGIN" "'"$profile"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" -eq 1 ]]
}
