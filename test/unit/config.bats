#!/usr/bin/env bash
# Unit tests for lib/config.sh and config validation helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "appid_in_list_file finds appid in list" {
	local list
	list="$(mktemp)"
	printf '%s\n' 12345 67890 > "$list"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		appid_in_list_file 67890 "'"$list"'" && echo found || echo missing
	'
	[[ $status -eq 0 ]]
	[[ "$output" == found ]]
	rm -f "$list"
}

@test "appid_in_list_file ignores comments and blanks" {
	local list
	list="$(mktemp)"
	cat > "$list" <<EOF
# comment
42424242

EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		appid_in_list_file 42424242 "'"$list"'" && echo found || echo missing
	'
	[[ $status -eq 0 ]]
	[[ "$output" == found ]]
	rm -f "$list"
}

@test "appid_in_list_file returns failure for missing appid" {
	local list
	list="$(mktemp)"
	printf '%s\n' 11111 > "$list"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		appid_in_list_file 22222 "'"$list"'" && echo found || echo missing
	'
	[[ $status -eq 0 ]]
	[[ "$output" == missing ]]
	rm -f "$list"
}

@test "load_env_file exports keys from file" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		cat > /tmp/test-$$.env <<EOF
GAMEMODE=1
# comment
INCLUDE=presets/standard.env
MANGOHUD=0
EOF
		load_env_file /tmp/test-$$.env 1
		echo "gamemode:$GAMEMODE mangohud:$MANGOHUD"
		rm -f /tmp/test-$$.env
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "gamemode:1 mangohud:0" ]]
}

@test "load_env_file force=0 preserves existing env" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAMEMODE=9
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		echo GAMEMODE=1 > /tmp/test-$$.env
		load_env_file /tmp/test-$$.env 0
		echo "gamemode:$GAMEMODE"
		rm -f /tmp/test-$$.env
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "gamemode:9" ]]
}

@test "load_env_file preserves hash characters inside quotes" {
	local tmp
	tmp="$(mktemp)"
	printf '%s\n' 'PRE_LAUNCH_CMD="printf #marker" # comment' > "$tmp"
	run env CONFIG_DIR="$CONFIG_DIR" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform keys config
		load_env_file "'"$tmp"'" 1
		printf "%s\n" "$PRE_LAUNCH_CMD"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "printf #marker" ]]
	rm -f "$tmp"
}

@test "is_safe_include_path rejects traversal and absolute paths" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		is_safe_include_path "presets/standard.env" && echo safe_ok || echo safe_bad
		is_safe_include_path "../../../etc/passwd" && echo trav_ok || echo trav_bad
		is_safe_include_path "/etc/passwd" && echo abs_ok || echo abs_bad
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"safe_ok"* ]]
	[[ "$output" == *"trav_bad"* ]]
	[[ "$output" == *"abs_bad"* ]]
}

@test "load_config_file refuses unsafe INCLUDE without loading escape target" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d"
	# Plant a file outside launch.d that must not be loaded via INCLUDE traversal.
	echo 'EVIL_KEY=1' > "$tmp/evil.env"
	echo 'INCLUDE=../evil.env' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		declare -A config_loaded=()
		config_layers=()
		declare -A config_key_sources=()
		load_config_file "$LAUNCHD_DIR/local.env" 1 2>&1
		echo "evil:${EVIL_KEY:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Refusing unsafe INCLUDE"* ]]
	[[ "$output" == *"evil:unset"* ]]
	rm -rf "$tmp"
}

@test "load_config_file accepts indented INCLUDE directives" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets"
	echo 'MANGOHUD=1' > "$tmp/launch.d/presets/test.env"
	echo '  INCLUDE=presets/test.env' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform keys config
		load_config_file "$LAUNCHD_DIR/local.env" 1
		printf "%s\n" "${MANGOHUD:-unset}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == 1 ]]
	rm -rf "$tmp"
}

@test "resolve_include_under_launchd rejects symlink escape" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets" "$tmp/outside"
	echo 'MANGOHUD=1' > "$tmp/outside/evil.env"
	ln -s "$tmp/outside" "$tmp/launch.d/presets/escape"
	run env CONFIG_DIR="$tmp" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform keys config
		resolve_include_under_launchd presets/escape/evil.env
	'
	[[ $status -eq 1 ]]
	rm -rf "$tmp"
}

@test "config_file_relative strips launch.d prefix" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		config_file_relative "'"$CONFIG_DIR"'/launch.d/presets/standard.env"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "presets/standard.env" ]]
}

@test "validate_single_config_file flags unknown keys" {
	local tmp cfg
	tmp="$(mktemp -d)"
	cfg="$tmp/bad.env"
	cat > "$cfg" <<'EOF'
NOT_A_REAL_LAUNCH_KEY=1
EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform keys config tools inspect
		validate_single_config_file "'"$cfg"'"
	'
	[[ "$output" == *"unknown key"* ]]
	rm -rf "$tmp"
}

@test "appid_env helpers use games dir" {
	local tmp games
	tmp="$(mktemp -d)"
	games="$tmp/games"
	mkdir -p "$games"
	printf 'GAMES=1\n' > "$games/12345.env"
	run bash -c '
		export CONFIG_DIR="'"$tmp"'"
		export LAUNCHLAYER_GAMES_DIR="'"$games"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib config
		printf "%s\n" "$(appid_env_write_path 12345)" "$(resolve_appid_env_path 12345)"
		appid_env_exists 12345 && echo exists || echo missing
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"$games/12345.env"* ]]
	[[ "$output" == *exists* ]]
	rm -rf "$tmp"
}

@test "config_file_display_name parses scaffold header" {
	local tmp file
	tmp="$(mktemp -d)"
	file="$tmp/42424242.env"
	cat > "$file" <<'EOF'
# Test Game (Steam AppID 42424242)
INCLUDE=presets/standard.env
EOF
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		config_file_display_name "'"$file"'" 42424242
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "Test Game" ]]
	rm -rf "$tmp"
}

@test "write_appid_env_scaffold creates preset include file" {
	local tmp games path
	tmp="$(mktemp -d)"
	games="$tmp/games"
	mkdir -p "$games"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		write_appid_env_scaffold 42424242 "Test Game" competitive
		cat "$(appid_env_write_path 42424242)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"INCLUDE=presets/competitive.env"* ]]
	[[ "$output" == *"Test Game (Steam AppID 42424242)"* ]]
	rm -rf "$tmp"
}

@test "reset_config_state clears launch globals" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config runtime
		GAMEMODE=1
		is_native=1
		is_anticheat=1
		launch=(gamemoderun)
		config_layers=("layer.env")
		reset_config_state
		echo "gamemode:${GAMEMODE:-unset} native:$is_native anticheat:$is_anticheat launch:${#launch[@]} layers:${#config_layers[@]}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "gamemode:unset native:0 anticheat:0 launch:0 layers:0" ]]
}

@test "apply_defaults sets DLSS_SWAPPER off" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		unset DLSS_SWAPPER
		apply_defaults
		printf "default:%s\n" "$DLSS_SWAPPER"
		DLSS_SWAPPER=dll
		apply_defaults
		printf "preserved:%s\n" "$DLSS_SWAPPER"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'default:0\npreserved:dll' ]]
}

@test "apply_defaults sets Bazzite Deck/FPS knobs empty/off" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		unset DISABLE_STEAM_DECK FRAME_RATE
		apply_defaults
		printf "defaults:%s [%s]\n" "$DISABLE_STEAM_DECK" "${FRAME_RATE-}"
		DISABLE_STEAM_DECK=1 FRAME_RATE=120
		apply_defaults
		printf "preserved:%s %s\n" "$DISABLE_STEAM_DECK" "$FRAME_RATE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'defaults:0 []\npreserved:1 120' ]]
}

@test "apply_defaults sets Arch latency knobs off" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		unset LD_BIND_NOW VKBASALT LATENCYFLEX DISABLE_VBLANK
		apply_defaults
		printf "defaults:%s %s %s %s\n" \
			"$LD_BIND_NOW" "$VKBASALT" "$LATENCYFLEX" "$DISABLE_VBLANK"
		LD_BIND_NOW=1 VKBASALT=1
		apply_defaults
		printf "preserved:%s %s\n" "$LD_BIND_NOW" "$VKBASALT"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'defaults:0 0 0 0\npreserved:1 1' ]]
}

@test "apply_defaults sets upscaler and shader-boost knobs off" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys config
		unset SHADER_CACHE_BOOST SHADER_CACHE_BOOST_GB PROTON_DLSS_UPGRADE \
			PROTON_FSR4_UPGRADE PROTON_XESS_UPGRADE PROTON_NVIDIA_LIBS
		apply_defaults
		printf "boost:%s gb:%s dlss:%s fsr4:%s xess:%s libs:%s\n" \
			"$SHADER_CACHE_BOOST" "$SHADER_CACHE_BOOST_GB" \
			"$PROTON_DLSS_UPGRADE" "$PROTON_FSR4_UPGRADE" \
			"$PROTON_XESS_UPGRADE" "$PROTON_NVIDIA_LIBS"
		SHADER_CACHE_BOOST=1 PROTON_DLSS_UPGRADE=1
		apply_defaults
		printf "preserved:%s %s\n" "$SHADER_CACHE_BOOST" "$PROTON_DLSS_UPGRADE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'boost:0 gb:12 dlss:0 fsr4:0 xess:0 libs:0\npreserved:1 1' ]]
}
