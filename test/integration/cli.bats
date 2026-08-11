#!/usr/bin/env bash
# Integration tests for top-level CLI behavior.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

@test "failed post-launch hook still records final state" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/config/launch.d" "$tmp/games"
	cat > "$tmp/config/launch.d/default.env" <<'EOF'
POST_LAUNCH_CMD=false
PLAYTIME_LOG=1
GAME_PERFORMANCE=0
GPU_POWER_CHECK=0
NVIDIA_POWER_MODE=0
GAMEMODE=0
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp/config" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$tmp/state" \
		"$SCRIPT" /bin/true
	[[ $status -eq 1 ]]
	[[ "$output" == *"POST_LAUNCH_CMD failed"* ]]
	grep -q 'exit=1' "$tmp/state/launchlayer/launch.log"
	grep -q 'seconds=' "$tmp/state/launchlayer/playtime.log"
	[[ ! -e "$tmp/state/launchlayer/active-launch.pid" ]]
	rm -rf "$tmp"
}

teardown() {
	bats_integration_teardown
}

@test "help exits zero" {
	run "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ "$output" == *"--show-config"* ]]
}

@test "version exits zero" {
	run "$SCRIPT" --version
	[[ $status -eq 0 ]]
	[[ "$output" == *"LaunchLayer"* ]]
	[[ "$output" == *"config_dir="* ]]
}

@test "unknown subcommand suggests similar flag" {
	run "$SCRIPT" --show-confg
	[[ $status -eq 1 ]]
	[[ "$output" == *"unknown subcommand"* ]]
	[[ "$output" == *"--show-config"* ]]
}

@test "help shows grouped sections" {
	run "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ "$output" == *"Onboarding & health"* ]]
	[[ "$output" == *"Games & config"* ]]
}

@test "launchlayer symlink resolves lib modules" {
	local tmp_home bindir
	tmp_home="$(mktemp -d)"
	bindir="$tmp_home/.local/bin"
	mkdir -p "$bindir"
	env HOME="$tmp_home" "$SCRIPT" --setup --symlink >/dev/null
	run env HOME="$tmp_home" "$bindir/launchlayer" --version
	[[ $status -eq 0 ]]
	[[ "$output" == *"LaunchLayer"* ]]
	[[ "$output" == *"script="* ]]
	rm -rf "$tmp_home"
}

@test "help documents tui" {
	run "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ "$output" == *"--tui"* ]]
}

@test "version reports 0.12.0" {
	run "$SCRIPT" --version
	[[ $status -eq 0 ]]
	[[ "$output" == *"0.12.0"* ]]
}

@test "quiet flag suppresses non-error output" {
	run "$SCRIPT" --quiet --version
	[[ $status -eq 0 ]]
	[[ "$output" == *"LaunchLayer"* ]]
}
