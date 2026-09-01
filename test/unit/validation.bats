#!/usr/bin/env bash
# Unit tests for lib/inspect/validation.sh helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "validate_single_config_file flags unknown keys" {
	local tmp
	tmp="$(temp_config_dir)"
	echo 'NOT_A_REAL_KEY=1' > "$tmp/launch.d/presets/bad.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/presets/bad.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"unknown key: NOT_A_REAL_KEY"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags conflicting force flags" {
	local tmp
	tmp="$(temp_config_dir)"
	cat > "$tmp/launch.d/local.env" <<'EOF'
FORCE_NATIVE=1
FORCE_PROTON=1
EOF
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"conflicting FORCE_NATIVE=1 and FORCE_PROTON=1"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags missing INCLUDE target" {
	local tmp
	tmp="$(temp_config_dir)"
	echo 'INCLUDE=missing-preset.env' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"INCLUDE target missing: missing-preset.env"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags duplicate gamemoderun in same file" {
	local tmp
	tmp="$(temp_config_dir)"
	cat > "$tmp/launch.d/local.env" <<'EOF'
GAMEMODE=1
LAUNCH_WRAPPERS_BEFORE=gamemoderun
EOF
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"LAUNCH_WRAPPERS includes gamemoderun while GAMEMODE=1"* ]]
	rm -rf "$tmp"
}

@test "validate_resolved_launch_wrappers flags layered wrapper overlap" {
	local tmp
	tmp="$(temp_config_dir)"
	mkdir -p "$tmp/games"
	printf '%s\n' 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	printf '%s\n' 'LAUNCH_WRAPPERS_BEFORE=gamemoderun' > "$tmp/games/42424242.env"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		_validate_resolved_launch_wrappers_for_appid 42424242 "$CONFIG_DIR/games/42424242.env" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"resolved: LAUNCH_WRAPPERS includes gamemoderun while GAMEMODE=1"* ]]
	[[ "$output" == *"resolved: duplicate gamemoderun"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags unsafe INCLUDE path" {
	local tmp
	tmp="$(temp_config_dir)"
	echo 'INCLUDE=../../../etc/passwd' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"unsafe INCLUDE path"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file accepts known keys" {
	local tmp
	tmp="$(temp_config_dir)"
	echo 'GAMEMODE=1' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 0 ]]
	[[ -z "$output" ]]
	[[ ! "$output" == *"unknown key"* ]]
	rm -rf "$tmp"
}

@test "validate_config batch reuses profiles and shared include resolution" {
	local tmp profile_calls include_calls
	tmp="$(temp_config_dir)"
	profile_calls="$tmp/profile-calls"
	include_calls="$tmp/include-calls"
	printf '%s\n' 'INCLUDE=presets/standard.env' > "$tmp/games/111.env"
	printf '%s\n' 'INCLUDE=presets/standard.env' > "$tmp/games/222.env"
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" \
		PROFILE_CALLS="$profile_calls" INCLUDE_CALLS="$include_calls" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		detect_default_profiles() {
			printf "call\n" >> "$PROFILE_CALLS"
			printf "arch-linux\n"
		}
		resolve_include_under_launchd() {
			printf "call\n" >> "$INCLUDE_CALLS"
			printf "%s/%s\n" "$LAUNCHD_DIR" "$1"
		}
		validate_config all 0 >/dev/null
		printf "profiles=%s includes=%s\n" \
			"$(wc -l < "$PROFILE_CALLS")" "$(wc -l < "$INCLUDE_CALLS")"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "profiles=1 includes=1" ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags invalid FRAME_RATE" {
	local tmp
	tmp="$(temp_config_dir)"
	printf '%s\n' 'FRAME_RATE=nope' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"FRAME_RATE must be a positive integer"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file accepts FRAME_RATE integer or empty" {
	local tmp
	tmp="$(temp_config_dir)"
	printf '%s\n' 'FRAME_RATE=120' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 0 ]]
	[[ -z "$output" ]]

	printf '%s\n' 'FRAME_RATE=' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 0 ]]
	[[ -z "$output" ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags sd0 with DISABLE_STEAM_DECK" {
	local tmp
	tmp="$(temp_config_dir)"
	cat > "$tmp/launch.d/local.env" <<'EOF'
DISABLE_STEAM_DECK=1
LAUNCH_WRAPPERS=sd0
EOF
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"sd0 while DISABLE_STEAM_DECK=1"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file accepts DLSS_SWAPPER values" {
	local tmp
	tmp="$(temp_config_dir)"
	printf '%s\n' 'DLSS_SWAPPER=1' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 0 ]]
	[[ -z "$output" ]]

	printf '%s\n' 'DLSS_SWAPPER=dll' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 0 ]]
	[[ -z "$output" ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file flags DLSS_SWAPPER with LAUNCH_WRAPPERS overlap" {
	local tmp
	tmp="$(temp_config_dir)"
	cat > "$tmp/launch.d/local.env" <<'EOF'
DLSS_SWAPPER=1
LAUNCH_WRAPPERS=dlss-swapper
EOF
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"LAUNCH_WRAPPERS includes dlss-swapper while DLSS_SWAPPER=1"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file rejects invalid tool-layer values" {
	local tmp
	tmp="$(temp_config_dir)"
	cat > "$tmp/launch.d/local.env" <<'EOF'
GPU_SELECT=voodoo
OPTISCALER_PROXY=kernel32
GAMESCOPE_RESHADE_TECHNIQUE=first
EOF
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 3 ]]
	[[ "$output" == *"GPU_SELECT must be"* ]]
	[[ "$output" == *"unsupported OPTISCALER_PROXY"* ]]
	[[ "$output" == *"GAMESCOPE_RESHADE_TECHNIQUE must be"* ]]
	rm -rf "$tmp"
}

@test "resolved validation rejects layered injector provider conflicts" {
	local tmp
	tmp="$(temp_config_dir)"
	mkdir -p "$tmp/games"
	cat > "$tmp/games/42424242.env" <<'EOF'
SPECIAL_K=1
SPECIAL_K_DLL=dxgi
OPTISCALER=1
OPTISCALER_PROXY=dxgi
EOF
	run env CONFIG_DIR="$tmp" LAUNCHLAYER_GAMES_DIR="$tmp/games" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		_validate_resolved_launch_wrappers_for_appid 42424242 "$GAMES_DIR/42424242.env" 2>&1
	'
	[[ $status -ne 0 ]]
	[[ "$output" == *"injector conflict on dxgi.dll"* ]]
	rm -rf "$tmp"
}

@test "validate_single_config_file rejects proxy path traversal" {
	local tmp
	tmp="$(temp_config_dir)"
	printf '%s\n' 'SPECIAL_K_DLL=../dxgi' 'RESHADE_DLL=subdir/d3d11' > "$tmp/launch.d/local.env"
	run env CONFIG_DIR="$tmp" VALIDATION_FILE="$tmp/launch.d/local.env" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam keys config runtime inspect
		validate_single_config_file "$VALIDATION_FILE" 2>&1
	'
	[[ $status -eq 2 ]]
	[[ "$output" == *"SPECIAL_K_DLL must be a proxy DLL leaf name"* ]]
	[[ "$output" == *"RESHADE_DLL must be a proxy DLL leaf name"* ]]
	rm -rf "$tmp"
}
