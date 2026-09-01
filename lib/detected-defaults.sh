# shellcheck shell=bash
# shellcheck source=common.sh
# shellcheck source=platform/paths.sh
# shellcheck source=hardware/cpu.sh
# lib/detected-defaults.sh — System-aware default env population.

[[ -n "${LAUNCHLAYER_DETECTED_DEFAULTS_LOADED:-}" ]] && return 0
LAUNCHLAYER_DETECTED_DEFAULTS_LOADED=1

declare -a _detected_default_keys=()
declare -a _detected_default_values=()
declare -a _detected_default_reasons=()

DETECTED_DEFAULTS_SOURCE=detected
LOCAL_CONFIG_FILE="$LAUNCHD_DIR/local.env"

# detected_defaults_reset — Clear the pending detected-default list.
detected_defaults_reset() {
	_detected_default_keys=()
	_detected_default_values=()
	_detected_default_reasons=()
}

# detected_defaults_add — Queue one detected default with a human-readable reason.
detected_defaults_add() {
	local key=$1 value=$2 reason=$3
	_detected_default_keys+=("$key")
	_detected_default_values+=("$value")
	_detected_default_reasons+=("$reason")
}

# set_detected_default — Apply one default when no .env layer set the key.
set_detected_default() {
	local key=$1 value=$2
	[[ -n "${config_key_sources[$key]+x}" ]] && return 0
	export "$key=$value"
	config_key_sources["$key"]="$DETECTED_DEFAULTS_SOURCE"
}

# filter_installed_vram_hog_units — Return only systemd --user units that exist.
filter_installed_vram_hog_units() {
	local units=${1:-}
	local -a filtered=() unit
	[[ -n "$units" ]] || return 0
	has_systemd_user || return 0
	for unit in $units; do
		systemctl --user cat "$unit" >/dev/null 2>&1 && filtered+=("$unit")
	done
	if ((${#filtered[@]} > 0)); then
		printf '%s' "${filtered[*]}"
	fi
	return 0
}

# is_multi_ccd_cpu — True when X3D-style CCD selection differs from all online CPUs.
is_multi_ccd_cpu() {
	local x3d all
	x3d="$(detect_x3d_cpus 2>/dev/null || true)"
	all="$(default_online_cpus 2>/dev/null || true)"
	[[ -n "$x3d" && -n "$all" && "$x3d" != "$all" ]]
}

# compute_detected_defaults — Build detected default key/value list from this machine.
compute_detected_defaults() {
	local vendor desktop audio deck=0 wsl=0 container=0 systemd_user=0
	local units steam_free_gb nic

	detected_defaults_reset

	vendor="$(detect_gpu_vendor)"
	desktop="$(detect_desktop_session)"
	audio="$(detect_audio_server)"
	is_steam_deck && deck=1
	is_wsl2 && wsl=1
	is_container && container=1
	has_systemd_user && systemd_user=1

	if [[ "$deck" == 1 ]]; then
		detected_defaults_add DISABLE_CPU_AFFINITY 1 "Steam Deck / handheld CPU topology"
		detected_defaults_add GAME_PERFORMANCE 0 "Steam Deck power profile"
		detected_defaults_add NETWORK_TUNE 0 "Steam Deck networking"
		detected_defaults_add GPU_POWER_CHECK 0 "Steam Deck GPU"
		detected_defaults_add NVIDIA_POWER_MODE 0 "Steam Deck GPU"
		detected_defaults_add GAMESCOPE_W 1280 "Steam Deck display"
		detected_defaults_add GAMESCOPE_H 800 "Steam Deck display"
		detected_defaults_add GAMESCOPE_R 60 "Steam Deck display"
	fi

	if [[ "$wsl" == 1 ]]; then
		detected_defaults_add GAMEMODE 0 "WSL2 lacks Linux GameMode integration"
		detected_defaults_add GAME_PERFORMANCE 0 "WSL2 CPU performance hooks"
		detected_defaults_add NETWORK_TUNE 0 "WSL2 networking"
		detected_defaults_add PIPEWIRE_LOW_LATENCY 0 "WSL2 audio stack"
		detected_defaults_add VRAM_HOGS 0 "WSL2 systemd user services"
		detected_defaults_add GPU_POWER_CHECK 0 "WSL2 GPU access"
		detected_defaults_add NVIDIA_POWER_MODE 0 "WSL2 GPU access"
		detected_defaults_add DISABLE_CPU_AFFINITY 1 "WSL2 CPU topology"
	fi

	if [[ "$container" == 1 ]]; then
		detected_defaults_add VRAM_HOGS 0 "Container environment"
		detected_defaults_add GPU_POWER_CHECK 0 "Container GPU access"
		detected_defaults_add NVIDIA_POWER_MODE 0 "Container GPU access"
	fi

	case "$(detect_os_family)" in
		bsd|darwin)
			detected_defaults_add GAMEMODE 0 "Non-Linux platform ($(detect_os_family))"
			detected_defaults_add GAMESCOPE 0 "Non-Linux platform"
			detected_defaults_add GAME_PERFORMANCE 0 "Non-Linux platform"
			detected_defaults_add VRAM_HOGS 0 "Non-Linux platform"
			detected_defaults_add NETWORK_TUNE 0 "Non-Linux platform"
			detected_defaults_add DISABLE_CPU_AFFINITY 1 "Non-Linux CPU affinity"
			detected_defaults_add VM_MAX_MAP_COUNT_FIX 0 "Linux-only vm.max_map_count"
			;;
		alpine|void)
			detected_defaults_add GAMEMODE 0 "Musl/minimal distro ($(detect_os_id))"
			detected_defaults_add GAME_PERFORMANCE 0 "Musl/minimal distro"
			detected_defaults_add VRAM_HOGS 0 "Musl/minimal distro"
			detected_defaults_add NETWORK_TUNE 0 "Musl/minimal distro"
			detected_defaults_add VM_MAX_MAP_COUNT_FIX 0 "Linux-only vm.max_map_count"
			;;
		nixos)
			detected_defaults_add VRAM_HOGS 0 "NixOS (declare VRAM units in home-manager)"
			;;
	esac

	if is_immutable_os; then
		detected_defaults_add VRAM_HOGS 0 "Immutable OS (rpm-ostree — layer systemd units)"
	fi

	if [[ "$deck" != 1 && "$wsl" != 1 ]]; then
		if [[ "$audio" == pipewire ]] && command_available pw-metadata; then
			detected_defaults_add PIPEWIRE_LOW_LATENCY 0 "Global PipeWire quantum tuning is opt-in"
		fi
		nic="$(detect_default_nic 2>/dev/null || true)"
		if [[ -n "$nic" ]] && command_available ethtool; then
			detected_defaults_add NETWORK_TUNE 0 "NIC tuning is hardware-specific and opt-in ($nic)"
		fi
		if is_multi_ccd_cpu; then
			detected_defaults_add DISABLE_CPU_AFFINITY 0 "Multi-CCD / X3D CPU detected"
		fi
	fi

	case "$vendor" in
		nvidia)
			if [[ "$deck" != 1 && "$wsl" != 1 ]]; then
				detected_defaults_add GPU_POWER_CHECK 1 "NVIDIA GPU"
				detected_defaults_add NVIDIA_POWER_MODE 1 "NVIDIA GPU"
				detected_defaults_add VRAM_PREFLIGHT_MIN_MB 2048 "NVIDIA VRAM preflight"
				detected_defaults_add GPU_VRAM_PROCESS_MIN_MB 512 "NVIDIA VRAM process guard"
			fi
			;;
		amd)
			if [[ "$deck" != 1 && "$wsl" != 1 ]]; then
				detected_defaults_add VRAM_PREFLIGHT_MIN_MB 1024 "AMD GPU VRAM preflight"
			fi
			detected_defaults_add NVIDIA_POWER_MODE 0 "Non-NVIDIA GPU"
			detected_defaults_add GPU_POWER_CHECK 0 "Non-NVIDIA GPU"
			;;
		intel)
			detected_defaults_add NVIDIA_POWER_MODE 0 "Intel GPU"
			detected_defaults_add GPU_POWER_CHECK 0 "Intel GPU"
			detected_defaults_add VRAM_PREFLIGHT_MIN_MB 0 "Intel integrated GPU"
			;;
	esac

	if [[ "$deck" != 1 && "$wsl" != 1 ]]; then
		steam_free_gb="$(df_avail_gb "$STEAM_ROOT" 2>/dev/null || true)"
		if [[ -n "$steam_free_gb" && "$steam_free_gb" =~ ^[0-9]+$ ]]; then
			if (( steam_free_gb < 50 )); then
				detected_defaults_add DISK_PREFLIGHT_MIN_GB 10 "Low free space on Steam library (${steam_free_gb}GB)"
			else
				detected_defaults_add DISK_PREFLIGHT_MIN_GB 5 "Steam library free-space guard"
			fi
		fi
	fi

	if [[ "$systemd_user" == 1 && "$deck" != 1 && "$wsl" != 1 ]]; then
		units="$(filter_installed_vram_hog_units "${VRAM_HOG_UNITS:-hyprwhspr.service app-dev.lizardbyte.app.Sunshine.service}" || true)"
		if [[ -n "$units" ]]; then
			detected_defaults_add VRAM_HOG_UNITS "$units" "Installed VRAM-heavy systemd user units"
		fi
	fi

	if [[ "$deck" != 1 && "$wsl" != 1 ]]; then
		detected_defaults_add SHADER_CACHE_BOOST 1 "Raise vendor shader cache size limits"
	fi

	if is_wayland_session && [[ "$desktop" != gamescope ]]; then
		detected_defaults_add GAMESCOPE_EXPOSE_WAYLAND 0 "Wayland desktop session ($desktop)"
	fi
}

# apply_detected_defaults — Fill unset knobs from compute_detected_defaults.
apply_detected_defaults() {
	local i key value
	compute_detected_defaults
	for (( i = 0; i < ${#_detected_default_keys[@]}; i++ )); do
		key="${_detected_default_keys[$i]}"
		value="${_detected_default_values[$i]}"
		set_detected_default "$key" "$value"
	done
}

# show_detected_defaults — Print recommended machine defaults.
show_detected_defaults() {
	local json=${1:-0} skip_header=${2:-0} i key value reason
	compute_detected_defaults
	if [[ "$json" == "1" ]]; then
		printf '{"defaults":['
		for (( i = 0; i < ${#_detected_default_keys[@]}; i++ )); do
			(( i )) && printf ','
			printf '{"key":%s,"value":%s,"reason":%s}' \
				"$(json_string "${_detected_default_keys[$i]}")" \
				"$(json_string "${_detected_default_values[$i]}")" \
				"$(json_string "${_detected_default_reasons[$i]}")"
		done
		printf ']}\n'
		return 0
	fi
	if [[ "$skip_header" != "1" ]]; then
		echo "=== Detected defaults ==="
	fi
	if ((${#_detected_default_keys[@]} == 0)); then
		echo "  (none — no machine-specific overrides beyond launch.d/default.env)"
		return 0
	fi
	for (( i = 0; i < ${#_detected_default_keys[@]}; i++ )); do
		key="${_detected_default_keys[$i]}"
		value="${_detected_default_values[$i]}"
		reason="${_detected_default_reasons[$i]}"
		printf '  %s=%s  # %s\n' "$key" "$value" "$reason"
	done
}

# write_local_config — Persist detected defaults to launch.d/local.env.
write_local_config() {
	local force=${1:-0} dry_run=${2:-0} path="$LOCAL_CONFIG_FILE" i
	local key value reason profiles

	if [[ -f "$path" && "$force" != "1" ]]; then
		echo "Config already exists: $path (use --force to overwrite)" >&2
		return 1
	fi

	load_profile_config
	load_config_file "$LAUNCHD_DIR/default.env" 0
	apply_defaults

	compute_detected_defaults
	profiles="$(detect_default_profiles 2>/dev/null || true)"

	if [[ "$dry_run" == "1" ]]; then
		echo "=== Write local config (dry-run) ==="
		echo "path=$path"
		[[ -n "$profiles" ]] && echo "profiles=$profiles"
		show_detected_defaults 0
		return 0
	fi

	{
		echo "# Machine-local defaults generated by LaunchLayer"
		echo "# Regenerate after hardware changes: launchlayer --write-local-config --force"
		echo "# Generated: $(timestamp_iso)"
		[[ -n "$profiles" ]] && echo "# Detected profiles: $profiles"
		echo
		for (( i = 0; i < ${#_detected_default_keys[@]}; i++ )); do
			key="${_detected_default_keys[$i]}"
			value="${_detected_default_values[$i]}"
			reason="${_detected_default_reasons[$i]}"
			echo "# $reason"
			printf '%s=%s\n' "$key" "$value"
			echo
		done
	} > "$path"

	echo "Wrote $path (${#_detected_default_keys[@]} settings)"
}
