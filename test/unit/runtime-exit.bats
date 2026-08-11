#!/usr/bin/env bash
# Unit tests for lib/vram.sh on_launch_exit teardown hook.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "on_launch_exit stops watchdog restores tuning and resumes vram hogs" {
	local tmp
	tmp="$(temp_state_dir)"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		VRAM_HOGS=1 \
		PIPEWIRE_LOW_LATENCY=1 \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib vram runtime
			mkdir -p "$STATE_DIR"
			echo 12345 > "$ACTIVE_LAUNCH_PID_FILE"
			set_vram_ref_count 1
			CALLS=()
			stop_launch_watchdog() { CALLS+=("watchdog"); }
			restore_nvidia_power_mode() { CALLS+=("nvidia"); }
			restore_pipewire_low_latency() { CALLS+=("pipewire"); }
			restore_runtime_tuning() { CALLS+=("runtime"); }
			resume_vram_hogs() { CALLS+=("vram"); set_vram_ref_count 0; }
			on_launch_exit
			printf "calls:%s\n" "${CALLS[*]}"
			[[ -f "$ACTIVE_LAUNCH_PID_FILE" ]] && echo pid:present || echo pid:cleared
			echo ref:$(get_vram_ref_count)
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"calls:watchdog nvidia pipewire runtime vram"* ]]
	[[ "$output" == *"pid:cleared"* ]]
	[[ "$output" == *"ref:0"* ]]
	rm -rf "$tmp"
}

@test "handle_subcommand routes validate-config through top-level dispatch" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib commands cli platform config inspect
		validate_config() { echo "validated:$1:$2"; }
		handle_subcommand --validate-config default --json
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "validated:default:1" ]]
}
