#!/usr/bin/env bash
# Unit tests for lib/launch.sh run_game_launch exec path.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "run_game_launch executes game binary and logs success" {
	local fake_steam tmp state_tmp game_bin
	fake_steam="$(fake_steam_root 42424242 "Exec Game")"
	tmp="$(temp_config_dir)"
	state_tmp="$(temp_state_dir)"
	game_bin="$fake_steam/steamapps/common/TestGame42424242/launch.sh"
	printf '#!/bin/sh\nexit 0\n' > "$game_bin"
	chmod +x "$game_bin"
	run env \
		CONFIG_DIR="$tmp" \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$state_tmp/state" \
		VRAM_HOGS=0 \
		LAUNCH_WATCHDOG=0 \
		bash -c '
			export CONFIG_DIR="'"$tmp"'"
			export STEAM_ROOT="'"$fake_steam"'"
			export LAUNCHLAYER_GAMES_DIR="'"$tmp"'/games"
			export LAUNCHLAYER_PROFILES=
			export SteamAppId=42424242
			export BENCHMARK=1
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform keys config steam hardware runtime detected-defaults gpu preflight vram launch
			optional_tool_installed() { return 1; }
			command_available() { return 1; }
			default_online_cpus() { echo 0-3; }
			apply_network_tuning() { :; }
			apply_pipewire_low_latency() { :; }
			apply_cpu_performance() { :; }
			apply_nvidia_power_mode() { :; }
			restore_nvidia_power_mode() { :; }
			restore_pipewire_low_latency() { :; }
			apply_proton_env() { :; }
			run_pre_launch_cmd() { :; }
			run_post_launch_cmd() { :; }
			warn_missing_tools() { :; }
			recover_stale_vram_state() { :; }
			check_concurrent_launch() { :; }
			check_vm_max_map_count() { :; }
			check_shader_cache() { :; }
			check_compatdata() { :; }
			check_vram_available() { :; }
			check_gpu_power() { :; }
			check_gpu_vram_processes() { :; }
			check_disk_space() { :; }
			apply_anticheat_guardrails() { :; }
			stop_launch_watchdog() { :; }
			start_launch_watchdog() { :; }
			run_game_launch "'"$game_bin"'" --game-arg
		'
	[[ $status -eq 0 ]]
	[[ -f "$state_tmp/state/launchlayer/launch.log" ]]
	grep -q 'appid=42424242' "$state_tmp/state/launchlayer/launch.log"
	grep -q 'exit=0' "$state_tmp/state/launchlayer/launch.log"
	rm -rf "$fake_steam" "$tmp" "$state_tmp"
}

@test "run_game_launch propagates non-zero game exit code" {
	local fake_steam tmp state_tmp game_bin
	fake_steam="$(fake_steam_root 42424242 "Fail Game")"
	tmp="$(temp_config_dir)"
	state_tmp="$(temp_state_dir)"
	game_bin="$fake_steam/steamapps/common/TestGame42424242/launch.sh"
	printf '#!/bin/sh\nexit 7\n' > "$game_bin"
	chmod +x "$game_bin"
	run env \
		CONFIG_DIR="$tmp" \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$state_tmp/state" \
		VRAM_HOGS=0 \
		LAUNCH_WATCHDOG=0 \
		bash -c '
			export CONFIG_DIR="'"$tmp"'"
			export STEAM_ROOT="'"$fake_steam"'"
			export LAUNCHLAYER_GAMES_DIR="'"$tmp"'/games"
			export LAUNCHLAYER_PROFILES=
			export SteamAppId=42424242
			export BENCHMARK=1
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform keys config steam hardware runtime detected-defaults gpu preflight vram launch
			optional_tool_installed() { return 1; }
			command_available() { return 1; }
			default_online_cpus() { echo 0-3; }
			apply_network_tuning() { :; }
			apply_pipewire_low_latency() { :; }
			apply_cpu_performance() { :; }
			apply_nvidia_power_mode() { :; }
			restore_nvidia_power_mode() { :; }
			restore_pipewire_low_latency() { :; }
			apply_proton_env() { :; }
			run_pre_launch_cmd() { :; }
			run_post_launch_cmd() { :; }
			warn_missing_tools() { :; }
			recover_stale_vram_state() { :; }
			check_concurrent_launch() { :; }
			check_vm_max_map_count() { :; }
			check_shader_cache() { :; }
			check_compatdata() { :; }
			check_vram_available() { :; }
			check_gpu_power() { :; }
			check_gpu_vram_processes() { :; }
			check_disk_space() { :; }
			apply_anticheat_guardrails() { :; }
			stop_launch_watchdog() { :; }
			start_launch_watchdog() { :; }
			run_game_launch "'"$game_bin"'"
		'
	[[ $status -eq 7 ]]
	grep -q 'exit=7' "$state_tmp/state/launchlayer/launch.log"
	rm -rf "$fake_steam" "$tmp" "$state_tmp"
}

@test "failed post-launch hook still records final state" {
	local fake_steam tmp state_tmp game_bin
	fake_steam="$(fake_steam_root 42424242 "Hook Fail Game")"
	tmp="$(temp_config_dir)"
	state_tmp="$(temp_state_dir)"
	game_bin="$fake_steam/steamapps/common/TestGame42424242/launch.sh"
	printf '#!/bin/sh\nexit 0\n' > "$game_bin"
	chmod +x "$game_bin"
	run env \
		CONFIG_DIR="$tmp" \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$state_tmp/state" \
		bash -c '
			export CONFIG_DIR="'"$tmp"'"
			export STEAM_ROOT="'"$fake_steam"'"
			export LAUNCHLAYER_GAMES_DIR="'"$tmp"'/games"
			export LAUNCHLAYER_PROFILES=
			export SteamAppId=42424242
			export BENCHMARK=1 PLAYTIME_LOG=1 VRAM_HOGS=0 LAUNCH_WATCHDOG=0
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform keys config steam hardware runtime detected-defaults gpu preflight vram launch
			optional_tool_installed() { return 1; }
			command_available() { return 1; }
			default_online_cpus() { echo 0-3; }
			apply_network_tuning() { :; }
			apply_pipewire_low_latency() { :; }
			apply_cpu_performance() { :; }
			apply_nvidia_power_mode() { :; }
			restore_nvidia_power_mode() { :; }
			restore_pipewire_low_latency() { :; }
			apply_proton_env() { :; }
			run_pre_launch_cmd() { :; }
			run_post_launch_cmd() { return 1; }
			warn_missing_tools() { :; }
			recover_stale_vram_state() { :; }
			apply_anticheat_guardrails() { :; }
			stop_launch_watchdog() { :; }
			start_launch_watchdog() { :; }
			run_game_launch "'"$game_bin"'"
		'
	[[ $status -eq 1 ]]
	[[ "$output" == *"POST_LAUNCH_CMD failed"* ]]
	grep -q 'exit=1' "$state_tmp/state/launchlayer/launch.log"
	grep -q 'seconds=' "$state_tmp/state/launchlayer/playtime.log"
	[[ ! -e "$state_tmp/state/launchlayer/active-launch.pid" ]]
	rm -rf "$fake_steam" "$tmp" "$state_tmp"
}

@test "run_game_launch trap cleans up pid file and vram ref on exit" {
	local fake_steam tmp state_tmp game_bin
	fake_steam="$(fake_steam_root 42424242 "Trap Game")"
	tmp="$(temp_config_dir)"
	state_tmp="$(temp_state_dir)"
	game_bin="$fake_steam/steamapps/common/TestGame42424242/launch.sh"
	printf '#!/bin/sh\nexit 0\n' > "$game_bin"
	chmod +x "$game_bin"
	run env \
		CONFIG_DIR="$tmp" \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$state_tmp/state" \
		VRAM_HOGS=1 \
		LAUNCH_WATCHDOG=0 \
		bash -c '
			export CONFIG_DIR="'"$tmp"'"
			export STEAM_ROOT="'"$fake_steam"'"
			export LAUNCHLAYER_GAMES_DIR="'"$tmp"'/games"
			export LAUNCHLAYER_PROFILES=
			export SteamAppId=42424242
			export BENCHMARK=1
			export VRAM_HOGS=1
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform keys config steam hardware runtime detected-defaults gpu preflight vram launch
			optional_tool_installed() { return 1; }
			command_available() { return 1; }
			default_online_cpus() { echo 0-3; }
			apply_network_tuning() { :; }
			apply_pipewire_low_latency() { :; }
			apply_cpu_performance() { :; }
			apply_nvidia_power_mode() { :; }
			restore_nvidia_power_mode() { :; }
			restore_pipewire_low_latency() { :; }
			apply_proton_env() { :; }
			run_pre_launch_cmd() { :; }
			run_post_launch_cmd() { :; }
			warn_missing_tools() { :; }
			recover_stale_vram_state() { :; }
			check_concurrent_launch() { :; }
			check_vm_max_map_count() { :; }
			check_shader_cache() { :; }
			check_compatdata() { :; }
			check_vram_available() { :; }
			check_gpu_power() { :; }
			check_gpu_vram_processes() { :; }
			check_disk_space() { :; }
			apply_anticheat_guardrails() { :; }
			stop_launch_watchdog() { :; }
			start_launch_watchdog() { :; }
			pause_vram_hogs() { set_vram_ref_count 1; }
			resume_vram_hogs() { set_vram_ref_count 0; }
			run_game_launch "'"$game_bin"'"
		'
	[[ $status -eq 0 ]]
	[[ ! -f "$state_tmp/state/launchlayer/active-launch.pid" ]]
	[[ ! -f "$state_tmp/state/launchlayer/vram-hog-refcount" ]] \
		|| [[ "$(<"$state_tmp/state/launchlayer/vram-hog-refcount")" == "0" ]]
	rm -rf "$fake_steam" "$tmp" "$state_tmp"
}

@test "run_game_launch starts watchdog when LAUNCH_WATCHDOG is enabled" {
	local fake_steam tmp state_tmp game_bin
	fake_steam="$(fake_steam_root 42424242 "Watchdog Game")"
	tmp="$(temp_config_dir)"
	state_tmp="$(temp_state_dir)"
	game_bin="$fake_steam/steamapps/common/TestGame42424242/launch.sh"
	printf '#!/bin/sh\nexit 0\n' > "$game_bin"
	chmod +x "$game_bin"
	run env \
		CONFIG_DIR="$tmp" \
		STEAM_ROOT="$fake_steam" \
		LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		XDG_STATE_HOME="$state_tmp/state" \
		VRAM_HOGS=0 \
		LAUNCH_WATCHDOG=1 \
		bash -c '
			export CONFIG_DIR="'"$tmp"'"
			export STEAM_ROOT="'"$fake_steam"'"
			export LAUNCHLAYER_GAMES_DIR="'"$tmp"'/games"
			export LAUNCHLAYER_PROFILES=
			export SteamAppId=42424242
			export BENCHMARK=1
			export LAUNCH_WATCHDOG=1
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform keys config steam hardware runtime detected-defaults gpu preflight vram launch
			optional_tool_installed() { return 1; }
			command_available() { return 1; }
			default_online_cpus() { echo 0-3; }
			apply_network_tuning() { :; }
			apply_pipewire_low_latency() { :; }
			apply_cpu_performance() { :; }
			apply_nvidia_power_mode() { :; }
			restore_nvidia_power_mode() { :; }
			restore_pipewire_low_latency() { :; }
			apply_proton_env() { :; }
			run_pre_launch_cmd() { :; }
			run_post_launch_cmd() { :; }
			warn_missing_tools() { :; }
			recover_stale_vram_state() { :; }
			check_concurrent_launch() { :; }
			check_vm_max_map_count() { :; }
			check_shader_cache() { :; }
			check_compatdata() { :; }
			check_vram_available() { :; }
			check_gpu_power() { :; }
			check_gpu_vram_processes() { :; }
			check_disk_space() { :; }
			apply_anticheat_guardrails() { :; }
			stop_launch_watchdog() { :; }
			start_launch_watchdog() { echo "watchdog:$1"; }
			run_game_launch "'"$game_bin"'"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"watchdog:"* ]]
	rm -rf "$fake_steam" "$tmp" "$state_tmp"
}
