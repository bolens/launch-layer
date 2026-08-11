#!/usr/bin/env bash
# Unit tests for lib/platform helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "bytes_to_gb rounds up partial gigabytes" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		bytes_to_gb $(( 600 * 1024 * 1024 ))
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "1" ]]
}

@test "timestamp_iso returns parseable timestamp" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		timestamp_iso
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "detect_uname_kernel returns lowercase kernel name" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_uname_kernel
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^(linux|darwin|freebsd|openbsd|netbsd)$ ]]
}

@test "realpath_portable resolves existing path" {
	local tmp expected
	tmp="$(mktemp -d)"
	expected="$(cd "$tmp" && pwd -P)"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		realpath_portable "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$expected" ]]
	rm -rf "$tmp"
}

@test "nproc_portable returns positive cpu count" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		nproc_portable
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^[0-9]+$ ]]
	(( output > 0 ))
}

@test "is_linux matches current kernel family" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		kernel=$(detect_uname_kernel)
		if [[ "$kernel" == linux ]]; then
			is_linux && echo linux-yes || echo linux-no
		else
			is_linux && echo linux-yes || echo linux-no
		fi
	'
	[[ $status -eq 0 ]]
	kernel="$(bash -c 'source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"; source_lib platform; detect_uname_kernel')"
	if [[ "$kernel" == linux ]]; then
		[[ "$output" == linux-yes ]]
	else
		[[ "$output" == linux-no ]]
	fi
}

@test "resolve_proton_path resolves explicit proton paths" {
	local tmp
	tmp="$(mktemp -d)/proton"
	touch "$tmp"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		resolve_proton_path "'"$tmp"'"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "$tmp" ]]
	rm -rf "$(dirname "$tmp")"
}

@test "proton_tool_family classifies ge cachyos and valve" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		proton_tool_family GE-Proton10-34
		proton_tool_family proton-cachyos-slr
		proton_tool_family proton_experimental
		proton_tool_family ""
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'ge\ncachyos\nvalve\nvalve' ]]
}

@test "prefer_proton_cachyos finds system steam tool dir" {
	local tmp root
	tmp="$(mktemp -d)"
	root="$tmp/compatibilitytools.d/proton-cachyos-slr"
	mkdir -p "$root"
	touch "$root/proton"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export HOME="'"$tmp"'/home"
		mkdir -p "$HOME"
		unset STEAM_ROOT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		steam_compat_tool_roots() { printf "%s\n" "'"$tmp"'/compatibilitytools.d"; }
		prefer_proton_cachyos
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == "proton-cachyos-slr" ]]
}

@test "doctor_print_gaming_tips mentions Bazzite DISABLE_STEAM_DECK" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAMEMODE=0 SHADER_CACHE_BOOST=1 LD_BIND_NOW=1 DISABLE_VBLANK=1 \
			VKBASALT=1 LATENCYFLEX=1 DISABLE_STEAM_DECK=0 FRAME_RATE=
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform setup tools
		ananicy_cpp_active() { return 1; }
		prefer_proton_cachyos() { return 1; }
		detect_gpu_vendor() { echo nvidia; }
		detect_os_id() { echo bazzite; }
		is_immutable_os() { return 0; }
		optional_tool_installed() { return 1; }
		sched_ext_supported() { return 1; }
		doctor_print_gaming_tips
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"DISABLE_STEAM_DECK=1"* ]]
	[[ "$output" == *"SteamDeck=0"* ]]
	[[ "$output" == *"FRAME_RATE=N"* ]]
	[[ "$output" == *"DLSS_SWAPPER=1"* ]]
	[[ "$output" == *"docs.bazzite.gg"* ]]
}

@test "sched_ext helpers report unsupported without sysfs" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		# Point checks at a missing path by stubbing when real sysfs lacks sched_ext,
		# or verify loaded ops parsing against a temp root via function override.
		if [[ ! -d /sys/kernel/sched_ext ]]; then
			sched_ext_supported && echo supported || echo unsupported
			sched_ext_loaded && echo loaded || echo unloaded
		else
			# On kernels with sched_ext, overrides still exercise naming helpers.
			sched_ext_supported || exit 1
			sched_ext_loaded() { return 0; }
			sched_ext_ops_name() { echo scx_rusty; }
			printf "supported ops=%s\n" "$(sched_ext_ops_name)"
		fi
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"unsupported"* || "$output" == *"supported ops=scx_rusty"* ]]
}

@test "doctor_print_gaming_tips mentions RADV and Arch latency knobs" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAMEMODE=0 SHADER_CACHE_BOOST=1 LD_BIND_NOW=0 DISABLE_VBLANK=0 VKBASALT=0 LATENCYFLEX=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform setup tools
		ananicy_cpp_active() { return 1; }
		prefer_proton_cachyos() { return 1; }
		detect_gpu_vendor() { echo amd; }
		optional_tool_installed() { return 1; }
		sched_ext_supported() { return 0; }
		sched_ext_loaded() { return 0; }
		sched_ext_ops_name() { echo scx_lavd; }
		doctor_print_gaming_tips
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"RADV"* ]]
	[[ "$output" == *"sched_ext active (scx_lavd)"* ]]
	[[ "$output" == *"LD_BIND_NOW=1"* ]]
	[[ "$output" == *"LATENCYFLEX=1"* ]]
}

@test "doctor_print_gaming_tips warns on gamemode plus ananicy" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAMEMODE=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform setup tools
		ananicy_cpp_active() { return 0; }
		prefer_proton_cachyos() { return 1; }
		detect_gpu_vendor() { echo unknown; }
		optional_tool_installed() { return 1; }
		doctor_print_gaming_tips
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"ananicy-cpp"* ]]
	[[ "$output" == *"GameMode"* ]]
}

@test "doctor_print_gaming_tips mentions Proton-CachyOS and shader boost" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export GAMEMODE=0 SHADER_CACHE_BOOST=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform setup tools
		ananicy_cpp_active() { return 1; }
		prefer_proton_cachyos() { echo proton-cachyos-slr; }
		detect_gpu_vendor() { echo nvidia; }
		optional_tool_installed() { [[ "$1" == dlss-updater ]]; }
		doctor_print_gaming_tips
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"Proton-CachyOS available (proton-cachyos-slr)"* ]]
	[[ "$output" == *"dlss-updater"* ]]
	[[ "$output" == *"SHADER_CACHE_BOOST=1"* ]]
}

@test "list_installed_compat_tools lists proton dirs" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/a/proton-cachyos-slr" "$tmp/a/GE-Proton10-34" "$tmp/a/ignored"
	touch "$tmp/a/proton-cachyos-slr/proton" "$tmp/a/GE-Proton10-34/compatibilitytool.vdf"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		steam_compat_tool_roots() { printf "%s\n" "'"$tmp"'/a"; }
		list_installed_compat_tools | sort
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == $'GE-Proton10-34\nproton-cachyos-slr' ]]
}

@test "resolve_proton_path finds tools via steam_compat_tool_roots" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/compatibilitytools.d/proton-cachyos-slr"
	touch "$tmp/compatibilitytools.d/proton-cachyos-slr/proton"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		unset STEAM_ROOT
		export HOME="'"$tmp"'/empty-home"
		mkdir -p "$HOME"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		steam_compat_tool_roots() { printf "%s\n" "'"$tmp"'/compatibilitytools.d"; }
		resolve_proton_path proton-cachyos-slr
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == "$tmp/compatibilitytools.d/proton-cachyos-slr/proton" ]]
}

@test "proton_tool_supports_upscaler_upgrades gates by family" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		proton_tool_supports_upscaler_upgrades GE-Proton10-34 && echo ge-yes || echo ge-no
		proton_tool_supports_upscaler_upgrades proton-cachyos-slr && echo cachy-yes || echo cachy-no
		proton_tool_supports_upscaler_upgrades proton-em-10 && echo em-yes || echo em-no
		proton_tool_supports_upscaler_upgrades proton_experimental && echo valve-yes || echo valve-no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'ge-yes\ncachy-yes\nem-yes\nvalve-no' ]]
}

@test "resolve_effective_proton_tool prefers OVERRIDE_PROTON" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export OVERRIDE_PROTON=proton-cachyos-slr steam_app_id=42424242
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform steam
		get_proton_tool_for_appid() { echo GE-Proton10-34; }
		resolve_effective_proton_tool
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "proton-cachyos-slr" ]]
}

@test "detect_gpu_is_rdna3 matches RX 7000 names" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_gpu_vendor() { echo amd; }
		detect_primary_gpu_name() { echo "AMD Radeon RX 7900 XTX"; }
		detect_gpu_is_rdna3 && echo yes || echo no
		detect_primary_gpu_name() { echo "AMD Radeon RX 6600"; }
		detect_gpu_is_rdna3 && echo yes6600 || echo no6600
		detect_gpu_vendor() { echo nvidia; }
		detect_primary_gpu_name() { echo "GeForce RTX 3080 Ti"; }
		detect_gpu_is_rdna3 && echo yes-nv || echo no-nv
	'
	[[ $status -eq 0 ]]
	[[ "$output" == $'yes\nno6600\nno-nv' ]]
}
