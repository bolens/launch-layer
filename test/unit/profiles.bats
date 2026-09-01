#!/usr/bin/env bash
# Unit tests for lib/platform/profiles.sh helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "detect_os_profile maps arch family" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_os_family() { echo arch; }
		detect_os_profile
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "arch-linux" ]]
}

@test "profile_list_contains finds profile in list" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		profile_list_contains "arch-linux nvidia-desktop" nvidia-desktop && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == yes ]]

	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		profile_list_contains "arch-linux" nvidia-desktop && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == no ]]
}

@test "detect_default_profiles honors LAUNCHLAYER_PROFILES override" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_PROFILES=custom-profile,other-profile
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_default_profiles
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "custom-profile other-profile" ]]
}

@test "detect_default_profiles does not auto-enable NIC tuning profiles" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		is_wsl2() { return 1; }
		is_steam_deck() { return 1; }
		is_flatpak_steam() { return 1; }
		is_immutable_os() { return 1; }
		detect_os_profile() { :; }
		has_systemd_user() { return 0; }
		detect_handheld_profile() { :; }
		detect_cpu_vendor() { echo unknown; }
		detect_gpu_vendor() { echo unknown; }
		detect_nic_type() { echo wired; }
		detect_nic_driver() { echo e1000e; }
		profiles="$(detect_default_profiles)"
		[[ "$profiles" != *nic-wired* && "$profiles" != *nic-e1000e* ]]
		printf "%s\n" safe
	'
	[[ $status -eq 0 ]]
	[[ "$output" == safe ]]
}

@test "detect_default_profile returns first auto profile" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_PROFILES=alpha beta
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_default_profile
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "alpha" ]]
}

@test "detect_cpu_vendor detects amd from /proc/cpuinfo" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		grep() {
			if [[ "$4" == "/proc/cpuinfo" && "$2" == "-i" && "$3" == "authenticamd" ]]; then return 0; fi
			return 1
		}
		detect_cpu_vendor
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "amd" ]]
}

@test "detect_cpu_vendor detects intel from /proc/cpuinfo" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		grep() {
			if [[ "$4" == "/proc/cpuinfo" && "$2" == "-i" && "$3" == "genuineintel" ]]; then return 0; fi
			return 1
		}
		detect_cpu_vendor
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "intel" ]]
}

@test "detect_nic_type classifies lo as loopback and honors LAUNCHLAYER_SYSFS_NET" {
	local sysfs
	sysfs="$(mktemp -d)"
	mkdir -p "$sysfs/wlan0/wireless"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_SYSFS_NET="'"$sysfs"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_nic_type lo
		echo ---
		detect_nic_type wlan0
		echo ---
		detect_nic_type eth0
	'
	rm -rf "$sysfs"
	[[ $status -eq 0 ]]
	[[ "$output" == *"loopback"* ]]
	[[ "$output" == *"wireless"* ]]
	[[ "$output" == *"wired"* ]]
}

@test "detect_handheld_profile maps product names" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		printf "%s\n" \
			"$(detect_handheld_profile "ASUS ROG Ally RC71L")" \
			"$(detect_handheld_profile "Jupiter")" \
			"$(detect_handheld_profile "Legion Go 83E1")" \
			"$(detect_handheld_profile "Desktop PC")" \
			"$(detect_handheld_profile "Lenovo Legion 5")" \
			"$(detect_handheld_profile "ROG Strix Ally")"
	'
	[[ $status -eq 0 ]]
	[[ "${lines[0]}" == "rog-ally" ]]
	[[ "${lines[1]}" == "steam-deck" ]]
	[[ "${lines[2]}" == "legion-go" ]]
	[[ "${lines[3]}" == "" ]]
	[[ "${lines[4]}" == "" ]]  # Legion laptop must not match legion-go
	[[ "${lines[5]}" == "" ]]  # Ally substring alone is not enough without "rog ally"
}

@test "gpu profile env files load KEY=VALUE without export prefix" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform config
		unset AMD_VULKAN_ICD mesa_glthread __GL_THREADED_OPTIMIZATIONS 2>/dev/null || true
		load_env_file "'"$BATS_TEST_DIRNAME"'/../../launch.d/profiles/amd-gpu.env" 1
		load_env_file "'"$BATS_TEST_DIRNAME"'/../../launch.d/profiles/nvidia-desktop.env" 1
		printf "amd=%s mesa=%s gl=%s\n" "${AMD_VULKAN_ICD:-}" "${mesa_glthread:-}" "${__GL_THREADED_OPTIMIZATIONS:-}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"amd=RADV"* ]]
	[[ "$output" == *"mesa=true"* ]]
	[[ "$output" == *"gl=1"* ]]
}
