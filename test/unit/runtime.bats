#!/usr/bin/env bash
# Unit tests for lib/runtime/ helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "print_config_layers lists relative paths" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime keys config
		config_layers=("'$CONFIG_DIR'/launch.d/default.env" "'$CONFIG_DIR'/launch.d/presets/standard.env")
		print_config_layers
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Config layers:"* ]]
	[[ "$output" == *"default.env"* ]]
	[[ "$output" == *"presets/standard.env"* ]]
}

@test "run_pre_launch_cmd is no-op when unset" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		unset PRE_LAUNCH_CMD
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		run_pre_launch_cmd
		echo done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == done ]]
}

@test "run_pre_launch_cmd executes hook" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export PRE_LAUNCH_CMD="echo prelaunch-marker"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		run_pre_launch_cmd
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"prelaunch-marker"* ]]
}

@test "printf_cache_path_bytes_json formats cache entries" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib cli platform
		entries=("/cache/shader|1073741824")
		printf_cache_path_bytes_json entries
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"/cache/shader"'* ]]
	[[ "$output" == *'"bytes":1073741824'* ]]
	python3 -c 'import json,sys; json.loads(sys.argv[1])' "$output"
}

@test "apply_unset_vars removes listed env vars" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export UNSET_VARS="FOO BAR"
		export FOO=1 BAR=2
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		apply_unset_vars
		echo "foo:${FOO:-unset} bar:${BAR:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "foo:unset bar:unset" ]]
}

@test "apply_anticheat_guardrails warns on DEBUG with EAC title" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export DEBUG=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		is_anticheat=1
		apply_anticheat_guardrails 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"DEBUG=1 with EAC title"* ]]
}

@test "apply_proton_env skips exports for native games" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		is_native=1
		FORCE_PROTON=0
		unset PROTON_ENABLE_WAYLAND PROTON_USE_NTSYNC DXVK_ASYNC 2>/dev/null || true
		apply_proton_env
		echo "wayland:${PROTON_ENABLE_WAYLAND:-unset} ntsync:${PROTON_USE_NTSYNC:-unset} dxvk:${DXVK_ASYNC:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "wayland:unset ntsync:unset dxvk:unset" ]]
}

@test "apply_proton_env benchmark profile strips overlays" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 BENCHMARK=1 MANGOHUD=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		apply_proton_env
		echo "mangohud:${MANGOHUD:-unset} dxvk:${DXVK_ASYNC:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "mangohud:unset dxvk:1" ]]
}

@test "apply_proton_env sets Proton defaults for non-native games" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		apply_proton_env
		echo "wayland:${PROTON_ENABLE_WAYLAND} dxvk:${DXVK_ASYNC}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "wayland:1 dxvk:1" ]]
}

@test "rotate_launch_log trims oversized launch.log" {
	local tmp log
	tmp="$(temp_state_dir)"
	log="$tmp/state/launchlayer/launch.log"
	mkdir -p "$(dirname "$log")"
	printf '%s\n' {1..10} > "$log"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		LAUNCH_LOG_MAX_LINES=3 \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform runtime
			rotate_launch_log
			wc -l < "$LAUNCH_LOG_FILE"
		'
	[[ $status -eq 0 ]]
	[[ "$output" -eq 3 ]]
	rm -rf "$tmp"
}

@test "log_launch_event appends structured launch line" {
	local tmp
	tmp="$(temp_state_dir)"
	run env \
		CONFIG_DIR="$CONFIG_DIR" \
		XDG_STATE_HOME="$tmp/state" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform runtime
			steam_app_id=42424242
			steam_game_name="Test Game"
			is_native=1
			is_anticheat=0
			log_launch_event 0 120
			cat "$LAUNCH_LOG_FILE"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"appid=42424242"* ]]
	[[ "$output" == *"duration=120s exit=0"* ]]
	rm -rf "$tmp"
}

@test "parse_game_extra_args splits GAME_EXTRA_ARGS" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAME_EXTRA_ARGS="--foo bar"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		parse_game_extra_args
		printf "%s\n" "${game_extra_argv[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'--foo\nbar' ]]
}

@test "build_launch_chain includes enabled installed wrappers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 GAMEMODE=1 MANGOHUD=1 BENCHMARK=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() {
			case "$1" in gamemoderun|mangohud|taskset) return 0 ;; *) return 1 ;; esac
		}
		command_available() { return 1; }
		default_online_cpus() { echo 0-3; }
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *gamemoderun* ]]
	[[ "$output" == *mangohud* ]]
}

@test "apply_pipewire_low_latency exports pulse latency on pipewire" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export PIPEWIRE_LOW_LATENCY=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		detect_audio_server() { echo pipewire; }
		optional_tool_installed() { return 1; }
		apply_pipewire_low_latency
		echo "latency:${PULSE_LATENCY_MSEC:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "latency:30" ]]
}

@test "run_post_launch_cmd executes hook" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export POST_LAUNCH_CMD="echo postlaunch-marker"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		run_post_launch_cmd
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"postlaunch-marker"* ]]
}

@test "apply_proton_env warns when MANGOHUD and DXVK_HUD are both enabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 MANGOHUD=1 DXVK_HUD=fps
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime
		apply_proton_env 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"duplicate overlays"* ]]
	[[ "$output" == *"DXVK_HUD=fps"* ]]
}

@test "print_dry_run shows launch chain and config layers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime keys config
		steam_app_id=42424242
		steam_game_name="Dry Run Game"
		is_native=0
		is_anticheat=1
		config_layers=("'$CONFIG_DIR'/launch.d/default.env")
		launch=(gamemoderun)
		game_extra_argv=(--foo)
		print_dry_run /bin/true
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"launchlayer dry run"* ]]
	[[ "$output" == *"Config layers"* ]]
	[[ "$output" == *"Launch chain"* ]]
	[[ "$output" == *"gamemoderun"* ]]
}

@test "print_dry_run environment section shows Arch and Bazzite exports" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime keys config
		steam_app_id=1 steam_game_name=x is_native=0 is_anticheat=0
		config_layers=()
		launch=(true)
		game_extra_argv=()
		export LD_BIND_NOW=1 ENABLE_VKBASALT=1 LFX=1 SteamDeck=0
		export vblank_mode=0 MESA_VK_WSI_PRESENT_MODE=immediate DXVK_FRAME_RATE=60
		print_dry_run
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"LD_BIND_NOW=1"* ]]
	[[ "$output" == *"ENABLE_VKBASALT=1"* ]]
	[[ "$output" == *"LFX=1"* ]]
	[[ "$output" == *"SteamDeck=0"* ]]
	[[ "$output" == *"MESA_VK_WSI_PRESENT_MODE=immediate"* ]]
	[[ "$output" == *"DXVK_FRAME_RATE=60"* ]]
}

@test "append_launch_wrappers adds installed LAUNCH_WRAPPERS_BEFORE" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCH_WRAPPERS_BEFORE="wrapper-a wrapper-b"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		command_available() {
			case "$1" in wrapper-a|wrapper-b) return 0 ;; *) return 1 ;; esac
		}
		launch=()
		append_launch_wrappers
		printf "%s\n" "${launch[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'wrapper-a\nwrapper-b' ]]
}

@test "build_launch_chain unsets MANGOHUD when gamescope uses --mangoapp" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 GAMESCOPE=1 GAMESCOPE_W=1920 GAMESCOPE_H=1080 GAMESCOPE_R=120
		export GAMESCOPE_ADAPTIVE_SYNC=0 BENCHMARK=0 MANGOHUD=1 MANGOHUD_CONFIG=fps
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() { [[ "$1" == gamescope ]]; }
		command_available() { return 1; }
		launch=()
		build_launch_chain
		printf "mangohud_env:%s\n" "${MANGOHUD-unset}"
		printf "config:%s\n" "${MANGOHUD_CONFIG:-unset}"
		printf "chain:%s\n" "${launch[*]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"mangohud_env:unset"* ]]
	[[ "$output" == *"config:fps"* ]]
	[[ "$output" == *"--mangoapp"* ]]
	[[ "$output" != *"mangohud"* || "$output" == *"--mangoapp"* ]]
}

@test "build_launch_chain adds gamescope flags when enabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 GAMESCOPE=1 GAMESCOPE_W=1920 GAMESCOPE_H=1080 GAMESCOPE_R=120
		export GAMESCOPE_ADAPTIVE_SYNC=1 GAMESCOPE_FSR=1 BENCHMARK=0 MANGOHUD=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() { [[ "$1" == gamescope ]]; }
		command_available() { return 1; }
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *gamescope* ]]
	[[ "$output" == *"-W"* ]]
	[[ "$output" == *"1920"* ]]
	[[ "$output" == *"--adaptive-sync"* ]]
	[[ "$output" == *"--fsr-sharpness"* ]]
}

@test "apply_cpu_performance uses powerprofilesctl fallback" {
	local tmp
	tmp="$(temp_state_dir)"
	run env XDG_STATE_HOME="$tmp/state" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAME_PERFORMANCE=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		command_available() { [[ "$1" == powerprofilesctl ]]; }
		optional_tool_installed() { [[ "$1" == powerprofilesctl ]]; }
		debug() { printf "%s\n" "$*"; }
		powerprofilesctl() {
			[[ "$1" == get ]] && echo balanced
			return 0
		}
		apply_cpu_performance 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"powerprofilesctl performance (fallback)"* ]]
	rm -rf "$tmp"
}

@test "restore_cpu_performance restores saved power profile" {
	local tmp
	tmp="$(temp_state_dir)"
	run env XDG_STATE_HOME="$tmp/state" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		echo balanced > "$CPU_TUNING_STATE_FILE"
		command_available() { [[ "$1" == powerprofilesctl ]]; }
		powerprofilesctl() { printf "%s\n" "$*" > "'"$tmp"'/restored"; }
		restore_cpu_performance
		[[ ! -e "$CPU_TUNING_STATE_FILE" ]]
		cat "'"$tmp"'/restored"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "set balanced" ]]
	rm -rf "$tmp"
}

@test "restore_network_tuning replays saved settings" {
	local tmp
	tmp="$(temp_state_dir)"
	run env XDG_STATE_HOME="$tmp/state" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		cat > "$NETWORK_TUNING_STATE_FILE" <<EOF
nic=eth0
tcp_low_latency=0
rx=128
tx=256
adaptive_rx=on
adaptive_tx=off
rx_usecs=12
rx_frames=3
eee=on
wifi_power_save=off
EOF
		command_available() { [[ "$1" == ethtool || "$1" == iw ]]; }
		sudo() {
			[[ "$1" == -n ]] && shift
			printf "%s\n" "$*" >> "'"$tmp"'/calls"
		}
		restore_network_tuning
		cat "'"$tmp"'/calls"
		[[ ! -e "$NETWORK_TUNING_STATE_FILE" ]]
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"sysctl -w net.ipv4.tcp_low_latency=0"* ]]
	[[ "$output" == *"ethtool -G eth0 rx 128 tx 256"* ]]
	[[ "$output" == *"iw dev eth0 set power_save off"* ]]
	rm -rf "$tmp"
}
