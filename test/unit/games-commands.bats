#!/usr/bin/env bash
# Unit tests for lib/commands/games.sh per-game config helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
	GAMES_TMP="$(temp_config_dir)"
	export CONFIG_DIR="$GAMES_TMP"
	export LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games"
	mkdir -p "$LAUNCHLAYER_GAMES_DIR"
	FAKE_STEAM="$(fake_steam_root 42424242 "Games Command Game")"
	export STEAM_ROOT="$FAKE_STEAM"
}

teardown() {
	[[ -n "${FAKE_STEAM:-}" ]] && rm -rf "$FAKE_STEAM"
	[[ -n "${GAMES_TMP:-}" ]] && rm -rf "$GAMES_TMP"
}

@test "init_appid_config creates scaffold from suggested preset" {
	run env \
		CONFIG_DIR="$GAMES_TMP" \
		LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games" \
		STEAM_ROOT="$FAKE_STEAM" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform steam keys config commands
			init_appid_config 42424242
			cat "'"$GAMES_TMP"'/games/42424242.env"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"INCLUDE=presets/"* ]]
	[[ "$output" == *"42424242"* ]]
}

@test "init_appid_config refuses overwrite without force" {
	run env \
		CONFIG_DIR="$GAMES_TMP" \
		LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games" \
		STEAM_ROOT="$FAKE_STEAM" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform steam keys config commands
			init_appid_config 42424242 standard 0
			init_appid_config 42424242 competitive 0 2>&1
		'
	[[ $status -eq 1 ]]
	[[ "$output" == *"Config already exists"* ]]
}

@test "set_include_preset updates INCLUDE for existing per-game env" {
	run env \
		CONFIG_DIR="$GAMES_TMP" \
		LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games" \
		STEAM_ROOT="$FAKE_STEAM" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib platform steam keys config commands
			init_appid_config 42424242 standard 0
			set_include_preset 42424242 competitive
			grep ^INCLUDE= "'"$GAMES_TMP"'/games/42424242.env"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"INCLUDE=presets/competitive.env"* ]]
}

@test "appid_env_upsert replaces duplicate keys" {
	run env \
		CONFIG_DIR="$GAMES_TMP" \
		LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib config commands
			file="'"$GAMES_TMP"'/games/42424242.env"
			printf "%s\n" "GAMEMODE=1" "MANGOHUD=0" > "$file"
			appid_env_upsert "$file" "GAMEMODE" "0"
			cat "$file"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == $'GAMEMODE=0\nMANGOHUD=0' ]]
}

@test "appid_env_upsert serializes concurrent key updates" {
	command -v flock >/dev/null 2>&1 || skip "flock is not installed"
	run env \
		CONFIG_DIR="$GAMES_TMP" \
		LAUNCHLAYER_GAMES_DIR="$GAMES_TMP/games" \
		bash -c '
			source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
			source_lib config
			file="'"$GAMES_TMP"'/games/42424242.env"
			printf "%s\n" "INCLUDE=presets/standard.env" > "$file"
			appid_env_upsert "$file" GAMEMODE 1 &
			first=$!
			appid_env_upsert "$file" MANGOHUD 1 &
			second=$!
			wait "$first" "$second"
			sort "$file"
		'
	[[ $status -eq 0 ]]
	[[ "$output" == *"GAMEMODE=1"* ]]
	[[ "$output" == *"MANGOHUD=1"* ]]
}
