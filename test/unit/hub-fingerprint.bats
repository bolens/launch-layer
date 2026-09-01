#!/usr/bin/env bash
# Unit tests for lib/hub/fingerprint.sh tier bucketing.
load '../helpers.bash'

setup() {
	bats_unit_setup
	source_lib platform hardware cli hub
}

@test "hub_display_tier buckets ultrawide" {
	run hub_display_tier 3440 1440 120
	[[ $status -eq 0 ]]
	[[ "$output" == "ultrawide" ]]
}

@test "hub_display_tier buckets 4k" {
	run hub_display_tier 3840 2160 60
	[[ $status -eq 0 ]]
	[[ "$output" == "4k" ]]
}

@test "hub_display_tier buckets 1440p" {
	run hub_display_tier 2560 1440 144
	[[ $status -eq 0 ]]
	[[ "$output" == "1440p" ]]
}

@test "hub_refresh_tier buckets high refresh" {
	run hub_refresh_tier 165
	[[ "$status" -eq 0 ]]
	[[ "$output" == "hi144+" ]]

	run hub_refresh_tier 120
	[[ "$output" == "mid75_120" ]]

	run hub_refresh_tier 60
	[[ "$output" == "std60" ]]
}

@test "hub_vram_tier buckets VRAM" {
	run hub_vram_tier 12288
	[[ "$output" == "12gb" ]]

	run hub_vram_tier 8192
	[[ "$output" == "8gb" ]]

	run hub_vram_tier 16384
	[[ "$output" == "16gb+" ]]
}

@test "hub_monitor_layout buckets monitor count" {
	run hub_monitor_layout 1
	[[ "$output" == "single" ]]

	run hub_monitor_layout 2
	[[ "$output" == "dual" ]]

	run hub_monitor_layout 3
	[[ "$output" == "triple+" ]]
}

@test "hub_primary_aspect buckets ultrawide" {
	run hub_primary_aspect 3440 1440
	[[ "$output" == "21:9" ]]

	run hub_primary_aspect 2560 1440
	[[ "$output" == "16:9" ]]
}

@test "hub_primary_aspect returns unknown for invalid input" {
	run hub_primary_aspect 0 0
	[[ "$output" == "unknown" ]]
}

@test "hub_parse_display reads WxH@RHz strings" {
	run hub_parse_display "2560x1440@165Hz"
	[[ $status -eq 0 ]]
	[[ "$output" == "2560 1440 165" ]]
}

@test "hub_profiles_array builds JSON string array" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib cli hub
		hub_profiles_array "arch-linux, nvidia-desktop"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *'"arch-linux"'* ]]
	[[ "$output" == *'"nvidia-desktop"'* ]]
}

@test "hub_fingerprint_level_rank orders tiers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib hub
		hub_fingerprint_level_rank minimal
	'
	[[ "$output" == "1" ]]

	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib hub
		hub_fingerprint_level_rank detailed
	'
	[[ "$output" == "3" ]]
}

@test "hub_fingerprint_level_at_least compares tiers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_HUB_FINGERPRINT_LEVEL=standard
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib hub
		hub_fingerprint_level_at_least minimal && echo minimal-ok || echo minimal-fail
		hub_fingerprint_level_at_least standard && echo standard-ok || echo standard-fail
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'minimal-ok\nstandard-ok' ]]

	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_HUB_FINGERPRINT_LEVEL=minimal
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib hub
		hub_fingerprint_level_at_least detailed && echo detailed-ok || echo detailed-fail
	'
	[[ $status -eq 0 ]]
	[[ "$output" == detailed-fail ]]
}

@test "hub_fingerprint_hash is stable for same input" {
	local fp='{"gpu_vendor":"nvidia","os_family":"arch","session_type":"wayland","desktop":"kde","profiles":["arch-linux"],"display_tier":"1440p","refresh_tier":"mid75_120","has_x3d":true,"vrr":true,"wsl2":false,"flatpak_steam":false,"steam_deck":false,"immutable":false,"container":false}'
	local h1 h2
	h1="$(hub_fingerprint_hash "$fp")"
	h2="$(hub_fingerprint_hash "$fp")"
	[[ "$h1" == "$h2" ]]
	[[ ${#h1} -eq 64 ]]
}

@test "hub_fingerprint_hash matches Convex canonical key order" {
	local fp='{"gpu_vendor":"nvidia","os_family":"arch","session_type":"wayland","desktop":"kde","profiles":["arch-linux"],"display_tier":"1440p","refresh_tier":"mid75_120","has_x3d":true,"vrr":true,"wsl2":false,"flatpak_steam":false,"steam_deck":false,"immutable":false,"container":false}'
	run hub_fingerprint_hash "$fp"
	[[ $status -eq 0 ]]
	[[ "$output" == "858056a201fe58437ad682936363e89095ca57930cbe5d00712e4c20316a9ac9" ]]
}

@test "hub_fingerprint_level_desc documents tiers" {
	run hub_fingerprint_level_desc minimal
	[[ "$output" == *"default"* ]]

	run hub_fingerprint_level_desc detailed
	[[ "$output" == *"GPU"* ]]
}
