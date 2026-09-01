#!/usr/bin/env bash
# Unit tests for lib/detected-defaults.sh.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "set_detected_default applies unset keys only" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults config keys
		declare -gA config_key_sources=()
		set_detected_default GAMEMODE 1
		config_key_sources[GAMEMODE]=presets/standard.env
		set_detected_default GAMEMODE 9
		echo "gamemode:$GAMEMODE source:${config_key_sources[GAMEMODE]:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "gamemode:1 source:presets/standard.env" ]]
}

@test "detected_defaults_add queues key value pairs" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults
		detected_defaults_reset
		detected_defaults_add GAMEMODE 1 "test reason"
		detected_defaults_add MANGOHUD 0 "other"
		printf "%s=%s reason=%s\n" \
			"${_detected_default_keys[0]}" "${_detected_default_values[0]}" "${_detected_default_reasons[0]}" \
			"${_detected_default_keys[1]}" "${_detected_default_values[1]}" "${_detected_default_reasons[1]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"GAMEMODE=1 reason=test reason"* ]]
	[[ "$output" == *"MANGOHUD=0 reason=other"* ]]
}

@test "filter_installed_vram_hog_units drops missing units" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults platform
		has_systemd_user() { return 0; }
		systemctl() { [[ "$3" == launchlayer-fake.service ]] && return 1; return 0; }
		filter_installed_vram_hog_units "launchlayer-fake.service launchlayer-real.service"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "launchlayer-real.service" ]]
}

@test "apply_detected_defaults fills unset keys only" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults config keys platform
		declare -gA config_key_sources=()
		GAMEMODE=9
		compute_detected_defaults() {
			detected_defaults_reset
			detected_defaults_add MANGOHUD 1 "unit test"
		}
		apply_detected_defaults
		echo "gamemode:$GAMEMODE mangohud:$MANGOHUD"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "gamemode:9 mangohud:1" ]]
}

@test "show_detected_defaults json emits defaults array" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults platform cli
		compute_detected_defaults() {
			detected_defaults_reset
			detected_defaults_add GAMEMODE 0 "test"
		}
		show_detected_defaults 1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"defaults"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["defaults"][0]["key"]=="GAMEMODE"' "$output"
}

@test "is_multi_ccd_cpu detects split x3d topology" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults hardware
		detect_x3d_cpus() { echo 0-7; }
		default_online_cpus() { echo 0-15; }
		is_multi_ccd_cpu && echo multi || echo single
	'
	[[ $status -eq 0 ]]
	[[ "$output" == multi ]]

	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults hardware
		detect_x3d_cpus() { echo 0-15; }
		default_online_cpus() { echo 0-15; }
		is_multi_ccd_cpu && echo multi || echo single
	'
	[[ $status -eq 0 ]]
	[[ "$output" == single ]]
}

@test "compute_detected_defaults adds SHADER_CACHE_BOOST off Steam Deck" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults platform
		is_steam_deck() { return 1; }
		is_wsl2() { return 1; }
		is_container() { return 1; }
		has_systemd_user() { return 1; }
		detect_gpu_vendor() { echo nvidia; }
		detect_desktop_session() { echo kde; }
		detect_audio_server() { echo pulse; }
		detect_os_family() { echo arch; }
		is_immutable_os() { return 1; }
		is_wayland_session() { return 1; }
		command_available() { return 1; }
		detect_default_nic() { return 1; }
		is_multi_ccd_cpu() { return 1; }
		df_avail_gb() { echo 100; }
		compute_detected_defaults
		i=0
		while (( i < ${#_detected_default_keys[@]} )); do
			[[ "${_detected_default_keys[$i]}" == SHADER_CACHE_BOOST ]] && {
				echo "${_detected_default_values[$i]}"
				exit 0
			}
			((i++))
		done
		echo missing
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "1" ]]
}

@test "compute_detected_defaults skips SHADER_CACHE_BOOST on Steam Deck" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults platform
		is_steam_deck() { return 0; }
		is_wsl2() { return 1; }
		is_container() { return 1; }
		has_systemd_user() { return 1; }
		detect_gpu_vendor() { echo amd; }
		detect_desktop_session() { echo gamescope; }
		detect_audio_server() { echo pulse; }
		detect_os_family() { echo steamos; }
		is_immutable_os() { return 1; }
		is_wayland_session() { return 1; }
		command_available() { return 1; }
		compute_detected_defaults
		i=0
		while (( i < ${#_detected_default_keys[@]} )); do
			[[ "${_detected_default_keys[$i]}" == SHADER_CACHE_BOOST ]] && {
				echo present
				exit 0
			}
			((i++))
		done
		echo absent
	'
	[[ $status -eq 0 ]]
	[[ "$output" == absent ]]
}

@test "detected defaults keep invasive network and PipeWire tuning disabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib detected-defaults platform
		is_steam_deck() { return 1; }
		is_wsl2() { return 1; }
		is_container() { return 1; }
		has_systemd_user() { return 1; }
		detect_gpu_vendor() { echo amd; }
		detect_desktop_session() { echo kde; }
		detect_audio_server() { echo pipewire; }
		detect_os_family() { echo arch; }
		is_immutable_os() { return 1; }
		is_wayland_session() { return 1; }
		command_available() { return 0; }
		detect_default_nic() { echo eth0; }
		is_multi_ccd_cpu() { return 1; }
		df_avail_gb() { echo 100; }
		compute_detected_defaults
		for key in NETWORK_TUNE PIPEWIRE_LOW_LATENCY; do
			value=missing
			for ((i = 0; i < ${#_detected_default_keys[@]}; i++)); do
				[[ "${_detected_default_keys[$i]}" == "$key" ]] && value="${_detected_default_values[$i]}"
			done
			printf "%s=%s\n" "$key" "$value"
		done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'NETWORK_TUNE=0\nPIPEWIRE_LOW_LATENCY=0' ]]
}
