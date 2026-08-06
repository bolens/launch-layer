#!/usr/bin/env bash
# Unit tests for lib/runtime/tuning.sh network and audio helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "apply_network_tuning is no-op when NETWORK_TUNE is disabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export NETWORK_TUNE=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime tools platform
		sudo() { echo unexpected-sudo; return 0; }
		apply_network_tuning
		echo done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == done ]]
	[[ "$output" != *"unexpected-sudo"* ]]
}

@test "apply_network_tuning warns when passwordless sudo is unavailable" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export NETWORK_TUNE=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime tools platform
		require_tool_or_skip() { return 0; }
		command_available() { return 0; }
		detect_default_nic() { echo eth0; }
		sudo() { return 1; }
		apply_network_tuning 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"NETWORK_TUNE=1 skipped: sudo requires a password"* ]]
}

@test "restore_pipewire_low_latency resets pipewire quantum via pw-metadata" {
	local tmp
	tmp="$(temp_state_dir)"
	run env XDG_STATE_HOME="$tmp/state" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export PIPEWIRE_LOW_LATENCY=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime tools platform
		touch "$PIPEWIRE_TUNING_STATE_FILE"
		detect_audio_server() { echo pipewire; }
		optional_tool_installed() { [[ "$1" == pw-metadata ]]; }
		pw-metadata() { printf "pw-metadata %s\n" "$*"; return 0; }
		restore_pipewire_low_latency
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"pw-metadata -n settings 0 clock.force-quantum 0"* ]]
	rm -rf "$tmp"
}

@test "find_malloc_library detects library under MALLOC_LIBRARY_SEARCH_ROOT" {
	local tmp
	tmp="$(mktemp -d)"
	touch "$tmp/libjemalloc.so"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export MALLOC_LIBRARY_SEARCH_ROOT="'"$tmp"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		find_malloc_library jemalloc
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == "$tmp/libjemalloc.so" ]]
}

@test "detect_hdr_support returns 0 by default when tools absent" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		command_available() { return 1; }
		detect_hdr_support
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "0" ]]
}

@test "apply_override_proton rewrites proton path in argv" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/GE-Proton"
	touch "$tmp/GE-Proton/proton"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export OVERRIDE_PROTON="'"$tmp"'/GE-Proton/proton"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		warn() { :; }
		debug() { :; }
		args=("/old/steam/proton" "run" "game.exe")
		apply_override_proton args
		printf "%s\n" "${args[@]}"
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == *"$tmp/GE-Proton/proton"* ]]
	[[ "$out" != *"/old/steam/proton"* ]]
}

@test "resolve_block_device_name maps nvme partition via lsblk PKNAME" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/block/nvme0n1"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_SYSFS_BLOCK="'"$tmp"'/block"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		lsblk() {
			[[ "$1" == "-ndo" && "$2" == "PKNAME" ]] || return 1
			echo "nvme0n1"
		}
		# Device path need not exist for basename; skip readlink-f failure by using a real tempfile
		dev="$(mktemp)"
		# Force basename path: create a fake node name via symlink
		ln -sf /dev/null "'"$tmp"'/nvme0n1p2"
		resolve_block_device_name "'"$tmp"'/nvme0n1p2"
		rm -f "$dev"
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == "nvme0n1" ]]
}

@test "resolve_block_device_name keeps whole-disk nvme names" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/block/nvme0n1"
	touch "$tmp/nvme0n1"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LAUNCHLAYER_SYSFS_BLOCK="'"$tmp"'/block"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		lsblk() { return 1; }
		resolve_block_device_name "'"$tmp"'/nvme0n1"
	'
	local st=$status out=$output
	rm -rf "$tmp"
	[[ $st -eq 0 ]]
	[[ "$out" == "nvme0n1" ]]
}

@test "apply_disable_steam_deck exports SteamDeck=0" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export DISABLE_STEAM_DECK=1
		unset SteamDeck
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_disable_steam_deck
		echo "SteamDeck=$SteamDeck"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "SteamDeck=0" ]]
}

@test "apply_frame_rate sets DXVK and VKD3D frame rates" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export FRAME_RATE=72
		unset DXVK_FRAME_RATE VKD3D_FRAME_RATE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_frame_rate
		printf "dxvk=%s vkd3d=%s\n" "$DXVK_FRAME_RATE" "$VKD3D_FRAME_RATE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "dxvk=72 vkd3d=72" ]]
}

@test "apply_frame_rate ignores invalid values" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export FRAME_RATE=nope
		unset DXVK_FRAME_RATE VKD3D_FRAME_RATE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_frame_rate 2>/dev/null
		[[ -z "${DXVK_FRAME_RATE:-}" && -z "${VKD3D_FRAME_RATE:-}" ]] && echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "apply_launch_env_tuning sets LD_BIND_NOW and DISABLE_VBLANK exports" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LD_BIND_NOW=1 DISABLE_VBLANK=1 VKBASALT=0 LATENCYFLEX=0
		unset vblank_mode __GL_SYNC_TO_VBLANK MESA_VK_WSI_PRESENT_MODE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_launch_env_tuning
		printf "bind=%s vblank=%s gl=%s mesa=%s\n" \
			"$LD_BIND_NOW" "$vblank_mode" "$__GL_SYNC_TO_VBLANK" "$MESA_VK_WSI_PRESENT_MODE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "bind=1 vblank=0 gl=0 mesa=immediate" ]]
}

@test "apply_vkbasalt sets ENABLE_VKBASALT" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export VKBASALT=1
		unset ENABLE_VKBASALT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_vkbasalt
		echo "ENABLE_VKBASALT=$ENABLE_VKBASALT"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "ENABLE_VKBASALT=1" ]]
}

@test "apply_latencyflex sets LFX and NVAPI for Proton" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export LATENCYFLEX=1 is_native=0 DISABLE_VBLANK=1
		unset LFX PROTON_ENABLE_NVAPI DXVK_NVAPI_ALLOW_OTHER_DRIVERS
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		apply_latencyflex
		printf "lfx=%s nvapi=%s allow=%s\n" \
			"$LFX" "$PROTON_ENABLE_NVAPI" "$DXVK_NVAPI_ALLOW_OTHER_DRIVERS"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "lfx=1 nvapi=1 allow=1" ]]
}

@test "apply_shader_cache_boost sets Mesa limit for AMD" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export SHADER_CACHE_BOOST=1 SHADER_CACHE_BOOST_GB=12
		unset MESA_SHADER_CACHE_MAX_SIZE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		detect_gpu_vendor() { echo amd; }
		apply_shader_cache_boost
		echo "$MESA_SHADER_CACHE_MAX_SIZE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "12G" ]]
}

@test "apply_shader_cache_boost sets NVIDIA disk cache size" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export SHADER_CACHE_BOOST=1 SHADER_CACHE_BOOST_GB=12
		unset __GL_SHADER_DISK_CACHE_SIZE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		detect_gpu_vendor() { echo nvidia; }
		apply_shader_cache_boost
		echo "$__GL_SHADER_DISK_CACHE_SIZE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "12000000000" ]]
}

@test "apply_upscaler_upgrades exports PROTON_DLSS_UPGRADE" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_DLSS_UPGRADE=1 DLSS_SWAPPER=0 OVERRIDE_PROTON=GE-Proton10-34
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo nvidia; }
		resolve_dlss_swapper_bin() { return 1; }
		apply_upscaler_upgrades
		echo "dlss=$PROTON_DLSS_UPGRADE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"dlss=1"* ]]
}

@test "apply_upscaler_upgrades maps FSR4 to RDNA3 on RDNA3 GPUs" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_FSR4_UPGRADE=1 OVERRIDE_PROTON=proton-cachyos-slr
		unset PROTON_FSR4_RDNA3_UPGRADE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo amd; }
		detect_gpu_is_rdna3() { return 0; }
		apply_upscaler_upgrades
		[[ "${PROTON_FSR4_RDNA3_UPGRADE:-}" == "1" ]] && echo rdna3 || echo plain
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"rdna3"* ]]
}

@test "apply_upscaler_upgrades exports plain FSR4 when not RDNA3" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_FSR4_UPGRADE=1 OVERRIDE_PROTON=GE-Proton10-34
		unset PROTON_FSR4_RDNA3_UPGRADE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo amd; }
		detect_gpu_is_rdna3() { return 1; }
		apply_upscaler_upgrades
		echo "fsr4=${PROTON_FSR4_UPGRADE:-0} rdna3=${PROTON_FSR4_RDNA3_UPGRADE:-0}"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "fsr4=1 rdna3=0" ]]
}

@test "apply_upscaler_upgrades exports PROTON_XESS_UPGRADE" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_XESS_UPGRADE=1 OVERRIDE_PROTON=proton-cachyos-slr
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo intel; }
		apply_upscaler_upgrades
		echo "xess=$PROTON_XESS_UPGRADE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "xess=1" ]]
}

@test "apply_upscaler_upgrades warns when Valve Proton lacks downloaders" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_DLSS_UPGRADE=1 OVERRIDE_PROTON=proton_experimental DLSS_SWAPPER=0
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo nvidia; }
		resolve_dlss_swapper_bin() { return 1; }
		apply_upscaler_upgrades 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"lacks fork upscaler downloaders"* ]]
}

@test "apply_upscaler_upgrades warns when combined with DLSS_SWAPPER" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 PROTON_DLSS_UPGRADE=1 DLSS_SWAPPER=1 OVERRIDE_PROTON=GE-Proton10-34
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo nvidia; }
		apply_upscaler_upgrades 2>&1
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"prefer one path"* ]]
}

@test "apply_shader_cache_boost is no-op when disabled" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export SHADER_CACHE_BOOST=0
		unset MESA_SHADER_CACHE_MAX_SIZE __GL_SHADER_DISK_CACHE_SIZE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		detect_gpu_vendor() { echo amd; }
		apply_shader_cache_boost
		[[ -z "${MESA_SHADER_CACHE_MAX_SIZE:-}" ]] && echo skipped || echo set
	'
	[[ $status -eq 0 ]]
	[[ "$output" == skipped ]]
}

@test "apply_proton_nvidia_libs is no-op on non-NVIDIA" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export PROTON_NVIDIA_LIBS=1 PROTON_NVIDIA_LIBS_NO_32BIT=1
		unset PROTON_NVIDIA_LIBS_EXPORT
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		detect_gpu_vendor() { echo amd; }
		# Pre-set so we can detect whether apply re-exports; function returns early.
		PROTON_NVIDIA_LIBS=1
		apply_proton_nvidia_libs
		echo done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == done ]]
}

@test "apply_proton_env applies shader boost for Proton titles" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export is_native=0 SHADER_CACHE_BOOST=1 SHADER_CACHE_BOOST_GB=8 BENCHMARK=0
		unset MESA_SHADER_CACHE_MAX_SIZE
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools steam
		detect_gpu_vendor() { echo amd; }
		apply_proton_env
		echo "$MESA_SHADER_CACHE_MAX_SIZE"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "8G" ]]
}

@test "apply_proton_nvidia_libs exports libs flags on NVIDIA" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export PROTON_NVIDIA_LIBS=1 PROTON_NVIDIA_LIBS_NO_32BIT=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib runtime platform tools
		detect_gpu_vendor() { echo nvidia; }
		apply_proton_nvidia_libs
		echo "libs=$PROTON_NVIDIA_LIBS no32=$PROTON_NVIDIA_LIBS_NO_32BIT"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "libs=1 no32=1" ]]
}
