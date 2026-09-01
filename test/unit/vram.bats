#!/usr/bin/env bash
# Unit tests for lib/vram.sh.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "vram ref count round-trip" {
	local tmp
	tmp="$(temp_state_dir)"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram
			set_vram_ref_count 2
			echo "after-set:$(get_vram_ref_count)"
			set_vram_ref_count 0
			echo "after-clear:$(get_vram_ref_count)"
			[[ -f "$VRAM_REF_COUNT_FILE" ]] && echo file:present || echo file:absent
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"after-set:2"* ]]
	[[ "$output" == *"after-clear:0"* ]]
	[[ "$output" == *"file:absent"* ]]
	rm -rf "$tmp"
}

@test "save and load paused vram units" {
	local tmp
	tmp="$(temp_state_dir)"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram
			paused_vram_units=(sunshine.service hyprwhspr.service)
			save_paused_vram_units
			paused_vram_units=()
			load_paused_vram_units_from_state
			printf "%s\n" "${paused_vram_units[@]}"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == $'sunshine.service\nhyprwhspr.service' ]]
	rm -rf "$tmp"
}

@test "recover_stale_vram_state resumes orphaned pause state" {
	local tmp
	tmp="$(temp_state_dir)"
	mkdir -p "$tmp/state/launchlayer"
	printf 'sunshine.service\n' > "$tmp/state/launchlayer/paused-vram-units"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram
			resume_vram_hogs_force() { echo force-resumed; }
			recover_stale_vram_state 2>&1
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"stale paused-vram state"* ]]
	[[ "$output" == *"force-resumed"* ]]
	rm -rf "$tmp"
}

@test "cleanup_stale_launch removes dead active pid file" {
	local tmp pid_file dead_pid
	tmp="$(temp_state_dir)"
	pid_file="$tmp/state/launchlayer/active-launch.pid"
	mkdir -p "$(dirname "$pid_file")"
	dead_pid=999999
	echo "$dead_pid" > "$pid_file"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram
			resume_vram_hogs_force() { :; }
			stop_launch_watchdog() { :; }
			restore_nvidia_power_mode() { :; }
			cleanup_stale_launch "'"$dead_pid"'"
			[[ -f "$ACTIVE_LAUNCH_PID_FILE" ]] && echo still-there || echo cleared
		'
	[[ $status -eq 0 ]]
	[[ "$output" == cleared ]]
	rm -rf "$tmp"
}

@test "cleanup_stale_launch restores tracked injectors for recorded appid" {
	local tmp dead_pid
	tmp="$(temp_state_dir)"
	dead_pid=999998
	mkdir -p "$tmp/state/launchlayer"
	printf '%s\n' "$dead_pid" > "$tmp/state/launchlayer/active-launch.pid"
	printf '%s\n' 42424242 > "$tmp/state/launchlayer/active-launch.appid"
	run env CONFIG_DIR="$CONFIG_DIR" XDG_STATE_HOME="$tmp/state" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib vram
		stop_launch_watchdog() { :; }
		restore_nvidia_power_mode() { :; }
		inject_cleanup_launch_tracks() { echo "inject:$1"; }
		cleanup_stale_launch "'"$dead_pid"'"
		test ! -e "$ACTIVE_LAUNCH_PID_FILE"
		test ! -e "$ACTIVE_LAUNCH_APPID_FILE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"inject:42424242"* ]]
	rm -rf "$tmp"
}

@test "resume_vram_hogs keeps services paused until refcount zero" {
	local tmp
	tmp="$(temp_state_dir)"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram
			set_vram_ref_count 2
			resume_vram_hogs
			echo "after-first:$(get_vram_ref_count)"
			resume_vram_hogs
			echo "after-second:$(get_vram_ref_count)"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"after-first:1"* ]]
	[[ "$output" == *"after-second:0"* ]]
	rm -rf "$tmp"
}
