# shellcheck shell=bash
# lib/runtime/tuning.sh — Network, audio, CPU, Proton, and anticheat env tuning.

[[ -n "${LAUNCHLAYER_RUNTIME_TUNING_LOADED:-}" ]] && return 0
LAUNCHLAYER_RUNTIME_TUNING_LOADED=1

CPU_TUNING_STATE_FILE="$STATE_DIR/cpu-tuning.saved"
NETWORK_TUNING_STATE_FILE="$STATE_DIR/network-tuning.saved"
PIPEWIRE_TUNING_STATE_FILE="$STATE_DIR/pipewire-tuning.saved"

_runtime_state_value() {
	local file=$1 key=$2 line
	[[ -f "$file" ]] || return 1
	while IFS= read -r line; do
		[[ "$line" == "$key="* ]] || continue
		printf '%s\n' "${line#*=}"
		return 0
	done < "$file"
	return 1
}

save_network_tuning_state() {
	local nic=$1 current_rx="" current_tx="" eee="" wifi=""
	local adaptive_rx="" adaptive_tx="" rx_usecs="" rx_frames=""
	mkdir -p "$STATE_DIR" 2>/dev/null || return 1
	if command_available ethtool; then
		read -r current_rx current_tx < <(ethtool -g "$nic" 2>/dev/null | awk '
			/Current hardware settings:/ { current=1; next }
			current && /^RX:/ && rx == "" { rx=$2 }
			current && /^TX:/ && tx == "" { tx=$2 }
			END { print rx, tx }
		')
		read -r adaptive_rx adaptive_tx < <(
			ethtool -c "$nic" 2>/dev/null | awk '/^Adaptive RX:/{print $3, $5; exit}'
		)
		rx_usecs="$(ethtool -c "$nic" 2>/dev/null | awk '/^rx-usecs:/{print $2; exit}')"
		rx_frames="$(ethtool -c "$nic" 2>/dev/null | awk '/^rx-frames:/{print $2; exit}')"
		eee="$(ethtool --show-eee "$nic" 2>/dev/null | awk -F': ' '/EEE status:/{print ($2 ~ /^enabled/) ? "on" : "off"; exit}')"
	fi
	if command_available iw; then
		wifi="$(iw dev "$nic" get power_save 2>/dev/null | awk '{print $3; exit}')"
	fi
	if ! {
		printf 'nic=%s\n' "$nic"
		printf 'rx=%s\n' "$current_rx"
		printf 'tx=%s\n' "$current_tx"
		printf 'adaptive_rx=%s\n' "$adaptive_rx"
		printf 'adaptive_tx=%s\n' "$adaptive_tx"
		printf 'rx_usecs=%s\n' "$rx_usecs"
		printf 'rx_frames=%s\n' "$rx_frames"
		printf 'eee=%s\n' "$eee"
		printf 'wifi_power_save=%s\n' "$wifi"
	} > "$NETWORK_TUNING_STATE_FILE"; then
		rm -f "$NETWORK_TUNING_STATE_FILE"
		return 1
	fi
	chmod 600 "$NETWORK_TUNING_STATE_FILE" || {
		rm -f "$NETWORK_TUNING_STATE_FILE"
		return 1
	}
}

restore_network_tuning() {
	[[ -f "$NETWORK_TUNING_STATE_FILE" ]] || return 0
	local nic rx tx adaptive_rx adaptive_tx rx_usecs rx_frames eee wifi
	nic="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" nic || true)"
	rx="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" rx || true)"
	tx="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" tx || true)"
	adaptive_rx="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" adaptive_rx || true)"
	adaptive_tx="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" adaptive_tx || true)"
	rx_usecs="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" rx_usecs || true)"
	rx_frames="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" rx_frames || true)"
	eee="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" eee || true)"
	wifi="$(_runtime_state_value "$NETWORK_TUNING_STATE_FILE" wifi_power_save || true)"
	rm -f "$NETWORK_TUNING_STATE_FILE"
	[[ -n "$nic" ]] || return 0
	if command_available ethtool; then
		[[ "$rx" =~ ^[0-9]+$ && "$tx" =~ ^[0-9]+$ ]] \
			&& sudo -n ethtool -G "$nic" rx "$rx" tx "$tx" >/dev/null 2>&1 || true
		[[ -n "$adaptive_rx" && -n "$adaptive_tx" ]] \
			&& sudo -n ethtool -C "$nic" adaptive-rx "$adaptive_rx" adaptive-tx "$adaptive_tx" >/dev/null 2>&1 || true
		[[ "$rx_usecs" =~ ^[0-9]+$ && "$rx_frames" =~ ^[0-9]+$ ]] \
			&& sudo -n ethtool -C "$nic" rx-usecs "$rx_usecs" rx-frames "$rx_frames" >/dev/null 2>&1 || true
		[[ "$eee" == on || "$eee" == off ]] \
			&& sudo -n ethtool --set-eee "$nic" eee "$eee" >/dev/null 2>&1 || true
	fi
	[[ "$wifi" == on || "$wifi" == off ]] \
		&& command_available iw \
		&& sudo -n iw dev "$nic" set power_save "$wifi" >/dev/null 2>&1 || true
}

apply_network_tuning() {
	[[ "${NETWORK_TUNE:-0}" == "1" ]] || return 0
	local has_sudo=1
	sudo -n true 2>/dev/null || has_sudo=0

	if (( has_sudo == 0 )); then
		warn "NETWORK_TUNE=1 skipped: sudo requires a password"
		return 0
	fi

	local nic="${GAME_NIC:-}"
	[[ -n "$nic" ]] || nic="$(detect_default_nic 2>/dev/null || true)"
	[[ -n "$nic" ]] || {
		warn "NETWORK_TUNE=1 skipped: no default NIC detected"
		return 0
	}

	if ! command_available ip; then
		warn "NETWORK_TUNE=1 skipped: ip is not installed$(tool_warn_suffix ip)"
		return 0
	fi
	ip link show "$nic" >/dev/null 2>&1 || {
		warn "NETWORK_TUNE=1 skipped: NIC '$nic' not found"
		return 0
	}
	if ! save_network_tuning_state "$nic"; then
		warn "NETWORK_TUNE=1 skipped: cannot save restore state"
		return 0
	fi

	if command_available ethtool; then
		local max_rx=256 max_tx=256 ethtool_out
		if ethtool_out=$(ethtool -g "$nic" 2>/dev/null); then
			max_rx=$(printf '%s\n' "$ethtool_out" | awk '/^RX:/{print $2; exit}')
			max_tx=$(printf '%s\n' "$ethtool_out" | awk '/^TX:/{print $2; exit}')
		fi
		sudo -n ip link set "$nic" up 2>/dev/null || true
		sudo -n ethtool -G "$nic" rx "$max_rx" tx "$max_tx" 2>/dev/null || true
		sudo -n ethtool -C "$nic" adaptive-rx off adaptive-tx off 2>/dev/null || true
		sudo -n ethtool -C "$nic" rx-usecs 0 rx-frames 1 2>/dev/null || true

		if [[ "${DISABLE_NIC_EEE:-1}" == "1" ]]; then
			sudo -n ethtool --set-eee "$nic" eee off >/dev/null 2>&1 || true
			debug "disabled energy efficient ethernet (EEE) on $nic"
		fi
	else
		warn "NETWORK_TUNE=1: ethtool is not installed$(tool_warn_suffix ethtool) — skipping ethtool ring buffer & adaptive moderation tuning"
	fi

	if [[ "${DISABLE_WIFI_POWER_SAVE:-1}" == "1" ]] && [[ "$(detect_nic_type "$nic" 2>/dev/null)" == "wireless" ]]; then
		if command_available iw; then
			sudo -n iw dev "$nic" set power_save off >/dev/null 2>&1 || true
			debug "disabled wifi power saving on $nic (via iw)"
		elif command_available iwconfig; then
			sudo -n iwconfig "$nic" power off >/dev/null 2>&1 || true
			debug "disabled wifi power saving on $nic (via iwconfig)"
		fi
	fi

	debug "network tuning applied on $nic"
}

# apply_pipewire_low_latency — Tighten audio buffer/quantum for lower latency.
apply_pipewire_low_latency() {
	[[ "${PIPEWIRE_LOW_LATENCY:-0}" == "1" ]] || return 0
	local audio
	audio="$(detect_audio_server)"
	case "$audio" in
		pipewire)
			export PULSE_LATENCY_MSEC=30
			if optional_tool_installed pw-metadata; then
				if mkdir -p "$STATE_DIR" 2>/dev/null \
					&& : > "$PIPEWIRE_TUNING_STATE_FILE" \
					&& chmod 600 "$PIPEWIRE_TUNING_STATE_FILE"; then
					pw-metadata -n settings 0 clock.force-quantum 512 2>/dev/null || true
				else
					rm -f "$PIPEWIRE_TUNING_STATE_FILE"
					warn "PIPEWIRE_LOW_LATENCY skipped quantum tuning: cannot save restore state"
				fi
			else
				debug "PIPEWIRE_LOW_LATENCY: pw-metadata unavailable — using PULSE_LATENCY_MSEC only"
			fi
			debug "pipewire low-latency mode enabled"
			;;
		pulse)
			export PULSE_LATENCY_MSEC=30
			debug "pulseaudio low-latency mode enabled (PULSE_LATENCY_MSEC=30)"
			;;
		*)
			debug "PIPEWIRE_LOW_LATENCY skipped: audio server is ${audio:-unknown}"
			;;
	esac
}

# restore_pipewire_low_latency — Reset PipeWire quantum on launch exit.
restore_pipewire_low_latency() {
	[[ -f "$PIPEWIRE_TUNING_STATE_FILE" ]] || return 0
	rm -f "$PIPEWIRE_TUNING_STATE_FILE"
	[[ "$(detect_audio_server)" == pipewire ]] || return 0
	if optional_tool_installed pw-metadata; then
		pw-metadata -n settings 0 clock.force-quantum 0 2>/dev/null || true
	fi
}

# apply_cpu_performance — Fallback when game-performance wrapper is absent.
apply_cpu_performance() {
	[[ "${GAME_PERFORMANCE:-1}" == "1" ]] || return 0
	command_available game-performance && return 0
	mkdir -p "$STATE_DIR" 2>/dev/null || {
		warn "GAME_PERFORMANCE=1 skipped: cannot save restore state"
		return 0
	}
	if command_available cpupower && sudo -n true 2>/dev/null; then
		find /sys/devices/system/cpu/cpufreq -maxdepth 2 -name scaling_governor -type f \
			-exec sh -c 'printf "%s=%s\n" "$1" "$(cat "$1")"' _ {} \; \
			> "$CPU_TUNING_STATE_FILE" 2>/dev/null || true
		if [[ -s "$CPU_TUNING_STATE_FILE" ]] && chmod 600 "$CPU_TUNING_STATE_FILE"; then
			sudo -n cpupower frequency-set -g performance >/dev/null 2>&1 \
				&& debug "cpupower performance (fallback)" && return 0
		fi
		rm -f "$CPU_TUNING_STATE_FILE"
	fi
	if command_available powerprofilesctl; then
		powerprofilesctl get > "$CPU_TUNING_STATE_FILE" 2>/dev/null || true
		if [[ -s "$CPU_TUNING_STATE_FILE" ]] && chmod 600 "$CPU_TUNING_STATE_FILE"; then
			powerprofilesctl set performance >/dev/null 2>&1 \
				&& debug "powerprofilesctl performance (fallback)" && return 0
		fi
		rm -f "$CPU_TUNING_STATE_FILE"
	fi
	debug "GAME_PERFORMANCE=1: no game-performance/cpupower/powerprofilesctl — continuing without CPU perf tuning"
}

restore_cpu_performance() {
	[[ -s "$CPU_TUNING_STATE_FILE" ]] || return 0
	local line path value
	if [[ "$(<"$CPU_TUNING_STATE_FILE")" != *=* ]] && command_available powerprofilesctl; then
		powerprofilesctl set "$(<"$CPU_TUNING_STATE_FILE")" >/dev/null 2>&1 || true
	else
		while IFS= read -r line; do
			path="${line%%=*}"
			value="${line#*=}"
			[[ "$path" == /sys/devices/system/cpu/cpufreq/*/scaling_governor ]] || continue
			printf '%s\n' "$value" | sudo -n tee "$path" >/dev/null 2>&1 || true
		done < "$CPU_TUNING_STATE_FILE"
	fi
	rm -f "$CPU_TUNING_STATE_FILE"
}

restore_runtime_tuning() {
	restore_cpu_performance
	restore_network_tuning
}

# apply_unset_vars — Remove env vars listed in UNSET_VARS (space-separated).
apply_unset_vars() {
	local var
	[[ -n "${UNSET_VARS:-}" ]] || return 0
	for var in ${UNSET_VARS}; do
		unset "$var" 2>/dev/null || true
		debug "unset $var"
	done
}

# apply_anticheat_guardrails — Conservative defaults for EAC/BattlEye titles.
apply_anticheat_guardrails() {
	[[ "$is_anticheat" == "1" ]] || return 0
	[[ "${DEBUG:-0}" == "1" ]] && warn "DEBUG=1 with EAC title may cause launch failures"
	export PROTON_LOG="${PROTON_LOG:-0}"
	if [[ -n "${DXVK_ASYNC+x}" && "${DXVK_ASYNC:-}" == "1" ]]; then
		warn "DXVK_ASYNC=1 on EAC title — unset via UNSET_VARS if unstable"
	fi
}

# apply_shader_cache_boost — Raise vendor shader-cache size limits (CachyOS wiki).
# See: https://wiki.cachyos.org/configuration/gaming/#increase-maximum-shader-cache-size
apply_shader_cache_boost() {
	[[ "${SHADER_CACHE_BOOST:-0}" == "1" ]] || return 0
	local gb="${SHADER_CACHE_BOOST_GB:-12}"
	local nvidia_bytes
	[[ "$gb" =~ ^[0-9]+$ ]] || gb=12
	nvidia_bytes=$((gb * 1000000000))

	case "$(detect_gpu_vendor 2>/dev/null || true)" in
		amd|intel)
			export MESA_SHADER_CACHE_MAX_SIZE="${MESA_SHADER_CACHE_MAX_SIZE:-${gb}G}"
			debug "SHADER_CACHE_BOOST: MESA_SHADER_CACHE_MAX_SIZE=$MESA_SHADER_CACHE_MAX_SIZE"
			;;
		nvidia)
			export __GL_SHADER_DISK_CACHE_SIZE="${__GL_SHADER_DISK_CACHE_SIZE:-$nvidia_bytes}"
			export __GL_SHADER_DISK_CACHE="${__GL_SHADER_DISK_CACHE:-1}"
			export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP="${__GL_SHADER_DISK_CACHE_SKIP_CLEANUP:-1}"
			debug "SHADER_CACHE_BOOST: __GL_SHADER_DISK_CACHE_SIZE=$__GL_SHADER_DISK_CACHE_SIZE"
			;;
		*)
			export MESA_SHADER_CACHE_MAX_SIZE="${MESA_SHADER_CACHE_MAX_SIZE:-${gb}G}"
			export __GL_SHADER_DISK_CACHE_SIZE="${__GL_SHADER_DISK_CACHE_SIZE:-$nvidia_bytes}"
			debug "SHADER_CACHE_BOOST: vendor unknown — set both Mesa and NVIDIA cache limits"
			;;
	esac
}

# apply_proton_nvidia_libs — Proton-CachyOS / GE NVIDIA library knobs.
apply_proton_nvidia_libs() {
	[[ "$(detect_gpu_vendor 2>/dev/null || true)" == nvidia ]] || return 0
	if [[ "${PROTON_NVIDIA_LIBS:-0}" == "1" ]]; then
		export PROTON_NVIDIA_LIBS=1
		debug "PROTON_NVIDIA_LIBS=1 (PhysX/CUDA libs)"
	fi
	if [[ "${PROTON_NVIDIA_LIBS_NO_32BIT:-0}" == "1" ]]; then
		export PROTON_NVIDIA_LIBS_NO_32BIT=1
		debug "PROTON_NVIDIA_LIBS_NO_32BIT=1 (64-bit only)"
	fi
}

# apply_upscaler_upgrades — PROTON_*_UPGRADE env for GE / CachyOS / EM forks.
#
# Prefer these when the active Proton ships upscaler downloaders. For NGX + latest
# DLSS presets without replacing game files, use DLSS_SWAPPER instead (CachyOS
# dlss-swapper). dlss-updater is GUI-only — detect/suggest, do not invoke at launch.
apply_upscaler_upgrades() {
	local tool="" family="" vendor=""
	local want_dlss=0 want_fsr4=0 want_fsr4_rdna3=0 want_xess=0
	local any=0

	[[ "${PROTON_DLSS_UPGRADE:-0}" == "1" ]] && want_dlss=1
	[[ "${PROTON_FSR4_UPGRADE:-0}" == "1" ]] && want_fsr4=1
	[[ "${PROTON_FSR4_RDNA3_UPGRADE:-0}" == "1" ]] && want_fsr4_rdna3=1
	[[ "${PROTON_XESS_UPGRADE:-0}" == "1" ]] && want_xess=1
	(( want_dlss || want_fsr4 || want_fsr4_rdna3 || want_xess )) || return 0

	tool="$(resolve_effective_proton_tool 2>/dev/null || true)"
	family="$(proton_tool_family "$tool")"
	vendor="$(detect_gpu_vendor 2>/dev/null || true)"

	if ! proton_tool_supports_upscaler_upgrades "$tool"; then
		warn "PROTON_*_UPGRADE enabled but Proton tool '${tool:-Valve default}' lacks fork upscaler downloaders — use Proton-CachyOS/GE/EM, or DLSS_SWAPPER=1 for NGX presets"
	fi

	if (( want_dlss )); then
		if resolve_dlss_swapper_bin >/dev/null 2>&1; then
			warn "DLSS_SWAPPER=${DLSS_SWAPPER} with PROTON_DLSS_UPGRADE=1 — both can update DLSS; prefer one path"
		fi
		export PROTON_DLSS_UPGRADE=1
		[[ "${PROTON_DLSS_INDICATOR:-0}" == "1" ]] && export PROTON_DLSS_INDICATOR=1
		any=1
	fi

	if (( want_fsr4_rdna3 )); then
		export PROTON_FSR4_RDNA3_UPGRADE=1
		any=1
	elif (( want_fsr4 )); then
		if [[ "$vendor" == amd ]] && detect_gpu_is_rdna3 2>/dev/null; then
			export PROTON_FSR4_RDNA3_UPGRADE=1
			debug "PROTON_FSR4_UPGRADE on RDNA3 → PROTON_FSR4_RDNA3_UPGRADE=1"
		else
			export PROTON_FSR4_UPGRADE=1
		fi
		any=1
	fi
	if (( want_fsr4 || want_fsr4_rdna3 )) && [[ "${PROTON_FSR4_INDICATOR:-0}" == "1" ]]; then
		export PROTON_FSR4_INDICATOR=1
	fi

	if (( want_xess )); then
		export PROTON_XESS_UPGRADE=1
		any=1
	fi

	(( any )) && debug "upscaler upgrades: tool=${tool:-default} family=$family dlss=$want_dlss fsr4=$want_fsr4/$want_fsr4_rdna3 xess=$want_xess"
}

# apply_ld_bind_now — Eager symbol resolution (Arch Gaming: first-call latency).
# See: https://wiki.archlinux.org/title/Gaming#Load_shared_objects_immediately_for_better_first_time_latency
apply_ld_bind_now() {
	[[ "${LD_BIND_NOW:-0}" == "1" ]] || return 0
	export LD_BIND_NOW=1
	debug "LD_BIND_NOW=1 (eager dynamic linking)"
}

# apply_vkbasalt — Enable vkBasalt Vulkan post-process layer (ENABLE_VKBASALT=1).
# Missing-layer warnings come from warn_enabled_missing_tools.
apply_vkbasalt() {
	[[ "${VKBASALT:-0}" == "1" ]] || return 0
	export ENABLE_VKBASALT=1
	debug "ENABLE_VKBASALT=1"
	if declare -f apply_vkbasalt_config >/dev/null 2>&1; then
		apply_vkbasalt_config
	fi
}

# apply_latencyflex — Enable LatencyFleX (LFX=1).
# See: https://github.com/ishitatsuyuki/LatencyFleX
# Missing-layer warnings come from warn_enabled_missing_tools.
apply_latencyflex() {
	[[ "${LATENCYFLEX:-0}" == "1" ]] || return 0
	export LFX=1
	# Reflex-path games under Proton need NVAPI; already default for Proton titles.
	if [[ "${is_native:-0}" != "1" || "${FORCE_PROTON:-0}" == "1" ]]; then
		export PROTON_ENABLE_NVAPI="${PROTON_ENABLE_NVAPI:-1}"
		export DXVK_NVAPI_ALLOW_OTHER_DRIVERS="${DXVK_NVAPI_ALLOW_OTHER_DRIVERS:-1}"
	fi
	debug "LFX=1 (LatencyFleX)"
	if [[ "${DISABLE_VBLANK:-0}" != "1" ]]; then
		debug "LATENCYFLEX=1 works best with DISABLE_VBLANK=1 (and in-game VSync/Reflex settings)"
	fi
}

# apply_disable_vblank — Reduce DRI/compositor wait (Arch Gaming: Reducing DRI latency).
# Mesa: vblank_mode=0 + immediate present; NVIDIA: __GL_SYNC_TO_VBLANK=0.
apply_disable_vblank() {
	[[ "${DISABLE_VBLANK:-0}" == "1" ]] || return 0
	export vblank_mode="${vblank_mode:-0}"
	export __GL_SYNC_TO_VBLANK=0
	export MESA_VK_WSI_PRESENT_MODE="${MESA_VK_WSI_PRESENT_MODE:-immediate}"
	debug "DISABLE_VBLANK=1 (vblank_mode=0 __GL_SYNC_TO_VBLANK=0 MESA_VK_WSI_PRESENT_MODE=immediate)"
}

# apply_disable_steam_deck — Hide Deck hardware identity (Bazzite sd0 / SteamDeck=0).
# See: https://docs.bazzite.gg/Gaming/launch-options-env-variables/
apply_disable_steam_deck() {
	[[ "${DISABLE_STEAM_DECK:-0}" == "1" ]] || return 0
	export SteamDeck=0
	debug "SteamDeck=0 (DISABLE_STEAM_DECK=1; Bazzite sd0 equivalent)"
}

# apply_frame_rate — DXVK/VKD3D in-process FPS caps (best latency per Bazzite docs).
# Sets both DXVK_FRAME_RATE and VKD3D_FRAME_RATE; restart required to change.
apply_frame_rate() {
	local fps="${FRAME_RATE:-}"
	[[ -n "$fps" && "$fps" != "0" ]] || return 0
	if ! [[ "$fps" =~ ^[1-9][0-9]*$ ]]; then
		warn "FRAME_RATE=$fps is not a positive integer — ignoring"
		return 0
	fi
	export DXVK_FRAME_RATE="$fps"
	export VKD3D_FRAME_RATE="$fps"
	debug "FRAME_RATE=$fps (DXVK_FRAME_RATE=$fps VKD3D_FRAME_RATE=$fps)"
}

# apply_launch_env_tuning — Env knobs for native and Proton (Arch / Bazzite gaming docs).
apply_launch_env_tuning() {
	apply_gpu_selection
	apply_ld_bind_now
	apply_vkbasalt
	apply_latencyflex
	apply_disable_vblank
	apply_disable_steam_deck
	apply_frame_rate
}

# apply_gpu_selection — Select a GPU vendor through standard loader/PRIME hints.
apply_gpu_selection() {
	local selection="${GPU_SELECT:-auto}"
	local driver_filter="${VK_LOADER_DRIVERS_SELECT:-${GPU_SELECT_DRIVER:-}}"
	[[ -n "$driver_filter" ]] && export VK_LOADER_DRIVERS_SELECT="$driver_filter"
	case "${selection,,}" in
		""|auto) ;;
		discrete)
			export DRI_PRIME="${DRI_PRIME:-1}"
			;;
		nvidia)
			export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
			export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
			export __VK_LAYER_NV_optimus="${__VK_LAYER_NV_optimus:-NVIDIA_only}"
			export VK_LOADER_DRIVERS_SELECT="${VK_LOADER_DRIVERS_SELECT:-*nvidia*}"
			;;
		amd)
			export VK_LOADER_DRIVERS_SELECT="${VK_LOADER_DRIVERS_SELECT:-*radeon*}"
			;;
		intel)
			export VK_LOADER_DRIVERS_SELECT="${VK_LOADER_DRIVERS_SELECT:-*intel*}"
			;;
		*)
			warn "GPU_SELECT=$selection unknown (auto|discrete|nvidia|amd|intel)"
			return 0
			;;
	esac
	debug "GPU_SELECT=$selection driver_filter=${VK_LOADER_DRIVERS_SELECT:-none}"
}

# apply_proton_env — Export Proton/DXVK/VKD3D/NVIDIA tuning variables.
#
# Skipped entirely for native games unless FORCE_PROTON=1.
# BENCHMARK=1 uses a stripped profile (no MangoHUD, no VRR).
apply_proton_env() {
	[[ "$is_native" == "1" && "${FORCE_PROTON:-0}" != "1" ]] && {
		debug "skipping Proton env (native game)"
		return 0
	}

	apply_shader_cache_boost
	apply_proton_nvidia_libs
	apply_upscaler_upgrades

	if [[ "${DEBUG:-0}" == "1" ]]; then
		export PROTON_LOG=1
		export PROTON_LOG_DIR="${PROTON_LOG_DIR:-$HOME/steam-proton-logs}"
		mkdir -p "$PROTON_LOG_DIR"
	fi

	if [[ "${BENCHMARK:-0}" == "1" ]]; then
		unset MANGOHUD MANGOHUD_CONFIG MANGOHUD_LOG
		apply_unset_vars
		return 0
	fi

	apply_unset_vars

	if [[ "${MANGOHUD:-0}" == "1" && "${DXVK_HUD:-0}" != "0" ]]; then
		warn "MANGOHUD=1 with DXVK_HUD=${DXVK_HUD} may show duplicate overlays — unset DXVK_HUD or disable MangoHUD"
	fi

	if [[ "${MANGOHUD_LOG:-0}" == "1" ]]; then
		export MANGOHUD_LOG=1
	fi
}

# warn_missing_tools — Surface missing optional dependencies before launch fails.
warn_missing_tools() {
	warn_enabled_missing_tools
}

# find_malloc_library — Search common paths for jemalloc or mimalloc libraries.
find_malloc_library() {
	local type=$1
	local paths=()
	if [[ -n "${MALLOC_LIBRARY_SEARCH_ROOT:-}" ]]; then
		paths+=(
			"${MALLOC_LIBRARY_SEARCH_ROOT}/lib${type}.so"
			"${MALLOC_LIBRARY_SEARCH_ROOT}/lib${type}.so.2"
		)
	fi
	paths+=(
		"/usr/lib/lib${type}.so"
		"/usr/lib/x86_64-linux-gnu/lib${type}.so"
		"/usr/lib/x86_64-linux-gnu/lib${type}.so.2"
		"/usr/lib/i386-linux-gnu/lib${type}.so"
		"/usr/lib32/lib${type}.so"
		"/usr/local/lib/lib${type}.so"
	)
	local path
	for path in "${paths[@]}"; do
		if [[ -f "$path" ]]; then
			echo "$path"
			return 0
		fi
	done
	if command -v ldconfig >/dev/null 2>&1; then
		if ldconfig -p 2>/dev/null | grep -q "lib${type}.so"; then
			echo "lib${type}.so"
			return 0
		fi
	fi
	return 1
}

# apply_malloc_allocator — Preload high-performance malloc implementations.
apply_malloc_allocator() {
	[[ -n "${MALLOC_ALLOCATOR:-}" ]] || return 0
	local lib_path
	if lib_path="$(find_malloc_library "$MALLOC_ALLOCATOR" 2>/dev/null)"; then
		export LD_PRELOAD="${lib_path}${LD_PRELOAD:+:$LD_PRELOAD}"
		debug "preloaded $MALLOC_ALLOCATOR allocator via $lib_path"
	else
		warn "MALLOC_ALLOCATOR=${MALLOC_ALLOCATOR} failed: library not found"
	fi
}

# detect_hdr_support — Return 1 only when HDR appears *enabled* (not mere EDID capability).
detect_hdr_support() {
	# Prefer compositor "enabled" signals. EDID "HDR Static Metadata" is capability only
	# (see detect_hdr_capable) and must not auto-enable Gamescope/DXVK HDR.
	if command_available kscreen-doctor; then
		local ks
		ks="$(kscreen-doctor -j 2>/dev/null || true)"
		if [[ -n "$ks" ]] && command_available jq; then
			if echo "$ks" | jq -e '
				[.outputs[]? | select(.enabled == true) | .hdr // .hdrMetadata // empty]
				| map(select(. == true or . == "enabled" or (type=="object" and .enabled==true)))
				| length > 0
			' >/dev/null 2>&1; then
				echo 1
				return 0
			fi
		fi
		if kscreen-doctor -o 2>/dev/null | grep -i "HDR" | grep -qiE 'enabled|active|on'; then
			echo 1
			return 0
		fi
	fi
	echo 0
}

# detect_hdr_capable — Return 1 if EDID advertises HDR Static Metadata (capability tip).
detect_hdr_capable() {
	local edid
	for edid in /sys/class/drm/card*-*/edid; do
		[[ -f "$edid" ]] || continue
		if command_available edid-decode; then
			if edid-decode "$edid" 2>/dev/null | grep -qi "HDR Static Metadata"; then
				echo 1
				return 0
			fi
		fi
	done
	echo 0
}

# apply_hdr_tuning — Set environment variables and enable gamescope HDR.
apply_hdr_tuning() {
	local hdr_support=0
	if [[ "${ENABLE_HDR:-}" == "1" ]]; then
		hdr_support=1
	elif [[ -z "${ENABLE_HDR:-}" ]]; then
		hdr_support="$(detect_hdr_support)"
		if [[ "$hdr_support" != "1" && "$(detect_hdr_capable 2>/dev/null || echo 0)" == "1" ]]; then
			debug "HDR capable (EDID) but not enabled in compositor — set ENABLE_HDR=1 to force"
		fi
	fi

	if (( hdr_support == 1 )); then
		export DXVK_HDR=1
		export ENABLE_HDR_WSI=1
		GAMESCOPE_HDR=1
		debug "HDR support enabled (DXVK_HDR=1 ENABLE_HDR_WSI=1)"
	fi
}

# resolve_block_device_name — Map a device node (or partition) to a /sys/block name.
resolve_block_device_name() {
	local dev_path=$1
	local sysfs_block="${LAUNCHLAYER_SYSFS_BLOCK:-/sys/block}"
	local sysfs_class_block="${LAUNCHLAYER_SYSFS_CLASS_BLOCK:-/sys/class/block}"
	local dev_name pk parent
	[[ -n "$dev_path" ]] || return 1
	dev_path="$(readlink -f "$dev_path" 2>/dev/null || true)"
	[[ -n "$dev_path" ]] || return 1
	dev_name="$(basename "$dev_path")"

	# Prefer lsblk parent disk for partitions (nvme0n1p2 → nvme0n1, sda1 → sda).
	if command -v lsblk >/dev/null 2>&1; then
		pk="$(lsblk -ndo PKNAME "$dev_path" 2>/dev/null | head -1 | tr -d '[:space:]')"
		if [[ -n "$pk" && -d "$sysfs_block/$pk" ]]; then
			echo "$pk"
			return 0
		fi
	fi

	# sysfs: partitions expose .../partition and parent is the whole disk.
	if [[ -e "$sysfs_class_block/$dev_name/partition" ]]; then
		parent="$(basename "$(readlink -f "$sysfs_class_block/$dev_name/..")")"
		if [[ -n "$parent" && -d "$sysfs_block/$parent" ]]; then
			echo "$parent"
			return 0
		fi
	fi

	if [[ -d "$sysfs_block/$dev_name" ]]; then
		echo "$dev_name"
		return 0
	fi
	return 1
}

# apply_disk_tuning — Optimize Linux block device I/O scheduler.
apply_disk_tuning() {
	[[ "${DISK_TUNE:-0}" == "1" ]] || return 0
	sudo -n true 2>/dev/null || {
		warn "DISK_TUNE=1 skipped: sudo requires a password"
		return 0
	}

	local tune_path="."
	if [[ -n "${steam_app_id:-}" ]]; then
		tune_path="$(get_game_dir_for_appid "$steam_app_id" 2>/dev/null || true)"
		[[ -n "$tune_path" ]] || tune_path="."
	fi

	local dev_path dev_name rot_file scheduler_file schedulers target_sched
	dev_path="$(df -P "$tune_path" 2>/dev/null | awk 'NR==2 {print $1}')"
	[[ -n "$dev_path" ]] || return 0
	dev_name="$(resolve_block_device_name "$dev_path" 2>/dev/null || true)"
	[[ -n "$dev_name" ]] || {
		debug "disk tuning skipped: could not resolve block device for $dev_path"
		return 0
	}

	rot_file="${LAUNCHLAYER_SYSFS_BLOCK:-/sys/block}/$dev_name/queue/rotational"
	scheduler_file="${LAUNCHLAYER_SYSFS_BLOCK:-/sys/block}/$dev_name/queue/scheduler"

	# Only write to validated sysfs scheduler nodes (keeps sudo tee scoped).
	[[ "$scheduler_file" =~ (^|/)sys/block/[A-Za-z0-9._+-]+/queue/scheduler$ ]] || return 0
	[[ -f "$rot_file" && -f "$scheduler_file" ]] || return 0

	if [[ "$(<"$rot_file")" == "1" ]]; then
		target_sched="bfq"
	else
		target_sched="none"
	fi

	schedulers="$(cat "$scheduler_file")"
	if [[ "$schedulers" == *"$target_sched"* ]]; then
		sudo -n tee "$scheduler_file" >/dev/null <<<"$target_sched" 2>/dev/null && \
			debug "disk tuning: set I/O scheduler of $dev_name to $target_sched"
	else
		if [[ "$target_sched" == "none" ]] && [[ "$schedulers" == *"kyber"* ]]; then
			sudo -n tee "$scheduler_file" >/dev/null <<<"kyber" 2>/dev/null && \
				debug "disk tuning: set I/O scheduler of $dev_name to kyber"
		elif [[ "$schedulers" == *"mq-deadline"* ]]; then
			sudo -n tee "$scheduler_file" >/dev/null <<<"mq-deadline" 2>/dev/null && \
				debug "disk tuning: set I/O scheduler of $dev_name to mq-deadline"
		fi
	fi
}
