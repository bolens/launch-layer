# shellcheck shell=bash
# shellcheck source=common.sh
# shellcheck source=keys.sh
# shellcheck source=steam/library.sh
# lib/config.sh — Layered .env config loading and default values.
#
# Config resolution order:
#   0. launch.d/profiles/*.env (LAUNCHLAYER_PROFILES or auto-detected, layered)
#   1. launch.d/default.env
#   2. launch.d/local.env (optional machine-local file from --write-local-config)
#   3. launch.d/presets/*.env (via INCLUDE= or auto-selected standard/native)
#   4. games/<AppID>.env (overrides everything above)
# Runtime: apply_detected_defaults() fills unset keys after apply_defaults().

[[ -n "${LAUNCHLAYER_CONFIG_LOADED:-}" ]] && return 0
LAUNCHLAYER_CONFIG_LOADED=1

# load_env_file — Parse KEY=VALUE lines from a file and export them.
#
# Skips comments, blank lines, and INCLUDE= directives (handled separately).
# When force=0, existing environment variables are not overwritten.
# When force=1, values from this file always win (used for per-appid overrides).
load_env_file() {
	local file=$1
	local force=${2:-0}

	[[ -f "$file" ]] || return 0

	local line key value
	while IFS= read -r line || [[ -n "$line" ]]; do
		# Strip comments only when they occur outside quoted values.
		local cleaned="" char quote="" escaped=0 i
		for ((i = 0; i < ${#line}; i++)); do
			char="${line:i:1}"
			if [[ "$quote" == '"' && "$escaped" == "1" ]]; then
				cleaned+="$char"
				escaped=0
				continue
			fi
			if [[ "$quote" == '"' && "$char" == '\' ]]; then
				cleaned+="$char"
				escaped=1
				continue
			fi
			if [[ -z "$quote" && "$char" == "#" ]]; then
				break
			fi
			if [[ "$char" == "'" || "$char" == '"' ]]; then
				if [[ -z "$quote" ]]; then
					quote="$char"
				elif [[ "$quote" == "$char" ]]; then
					quote=""
				fi
			fi
			cleaned+="$char"
		done
		line="$cleaned"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue
		[[ "$line" =~ ^INCLUDE= ]] && continue
		[[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue

		key="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2]}"
		# Remove optional surrounding quotes.
		value="${value#\"}"; value="${value%\"}"
		value="${value#\'}"; value="${value%\'}"

		if [[ "$force" == "1" ]] || [[ -z "${!key+x}" ]]; then
			export "$key=$value"
			config_key_sources["$key"]="$file"
		fi
	done < "$file"

	debug "loaded $file"
}

# is_safe_include_path — Reject absolute paths and parent-directory traversal.
is_safe_include_path() {
	local include_path=$1
	[[ -n "$include_path" ]] || return 1
	case "$include_path" in
		/*|~*|*".."*) return 1 ;;
	esac
	[[ "$include_path" =~ ^[a-zA-Z0-9/_.-]+$ ]] || return 1
	return 0
}

# resolve_include_under_launchd — Resolve INCLUDE target; must stay under LAUNCHD_DIR.
resolve_include_under_launchd() {
	local include_path=$1
	local candidate resolved base

	is_safe_include_path "$include_path" || return 1
	candidate="$LAUNCHD_DIR/$include_path"
	if declare -F realpath_portable >/dev/null 2>&1; then
		resolved="$(realpath_portable "$candidate" 2>/dev/null || true)"
		base="$(realpath_portable "$LAUNCHD_DIR" 2>/dev/null || true)"
	elif command -v python3 >/dev/null 2>&1; then
		resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$candidate" 2>/dev/null || true)"
		base="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$LAUNCHD_DIR" 2>/dev/null || true)"
	else
		return 1
	fi
	[[ -n "$resolved" && -n "$base" ]] || return 1
	[[ "$resolved" == "$base" || "$resolved" == "$base"/* ]] || return 1
	printf '%s\n' "$resolved"
}

# load_config_file — Recursively load a config file and its INCLUDE= chain.
#
# Tracks loaded files in config_loaded[] to prevent circular INCLUDE loops.
load_config_file() {
	local file=$1
	local force=$2
	local include_line include_path include_file

	[[ -f "$file" ]] || return 0
	[[ -n "${config_loaded[$file]+x}" ]] && return 0
	config_loaded["$file"]=1

	# Process INCLUDE= before local keys so the preset layer sits underneath.
	include_line="$(grep -E '^[[:space:]]*INCLUDE=' "$file" 2>/dev/null | head -1 || true)"
	if [[ -n "$include_line" ]]; then
		include_line="${include_line#"${include_line%%[![:space:]]*}"}"
		include_path="${include_line#INCLUDE=}"
		include_path="${include_path#"${include_path%%[![:space:]]*}"}"
		include_path="${include_path%"${include_path##*[![:space:]]}"}"
		include_path="${include_path#\"}"; include_path="${include_path%\"}"
		include_path="${include_path#\'}"; include_path="${include_path%\'}"
		if ! include_file="$(resolve_include_under_launchd "$include_path")"; then
			echo "Refusing unsafe INCLUDE path: $include_path (from $file)" >&2
		else
			load_config_file "$include_file" 0
		fi
	fi

	config_layers+=("$file")
	load_env_file "$file" "$force"
}

# appid_in_list_file — Return 0 if appid appears as a line in list_file.
appid_in_list_file() {
	local appid=$1
	local list_file=$2
	local line
	[[ -n "$appid" && -f "$list_file" ]] || return 1
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ "$line" == "$appid" ]] && return 0
	done < "$list_file"
	return 1
}

# Per-game configs live in GAMES_DIR (default: ~/.local/share/launchlayer/games).

# appid_env_write_path — Path for per-game configs.
appid_env_write_path() {
	printf '%s/%s.env' "$GAMES_DIR" "$1"
}

# resolve_appid_env_path — Per-game config path (existing or default write target).
resolve_appid_env_path() {
	appid_env_write_path "$1"
}

# appid_env_exists — True when a per-game config exists in GAMES_DIR.
appid_env_exists() {
	[[ -f "$(appid_env_write_path "$1")" ]]
}

# config_file_relative — Strip LAUNCHD_DIR prefix for display.
config_file_relative() {
	local file=$1
	if [[ "$file" == "$LAUNCHD_DIR/"* ]]; then
		echo "${file#"$LAUNCHD_DIR/"}"
	elif [[ "$file" == "$GAMES_DIR/"* ]]; then
		echo "games/$(basename "$file")"
	else
		basename "$file"
	fi
}

# detect_steam_app_id — Resolve AppID from env vars or Steam launch argv.
detect_steam_app_id() {
	local last_argv=""
	steam_app_id=""

	if [[ -n "${SteamAppId:-}" && "${SteamAppId}" =~ ^[0-9]+$ ]]; then
		steam_app_id="$SteamAppId"
		return 0
	fi
	if [[ -n "${STEAM_APPID:-}" && "${STEAM_APPID}" =~ ^[0-9]+$ ]]; then
		steam_app_id="$STEAM_APPID"
		return 0
	fi

	for argv_item in "$@"; do
		if [[ "$last_argv" == "-applaunch" && "$argv_item" =~ ^[0-9]+$ ]]; then
			steam_app_id="$argv_item"
			return 0
		fi
		if [[ "$argv_item" =~ (AppId|SteamAppId)=([0-9]+) ]]; then
			steam_app_id="${BASH_REMATCH[2]}"
			return 0
		fi
		last_argv="$argv_item"
	done
}

# reset_config_state — Clear layered config before a fresh load (show-config / dry-run).
reset_config_state() {
	local key
	config_loaded=()
	config_key_sources=()
	config_layers=()
	launch=()
	game_extra_argv=()
	is_native=0
	is_anticheat=0
	anticheat_type=""
	game_engine_hint=""
	steam_game_name=""

	for key in "${LAUNCHLAYER_CONFIG_KEYS[@]}"; do
		unset "$key" 2>/dev/null || true
	done
}

# load_profile_config — Load one or more machine profile layers when present.
load_profile_config() {
	local profiles profile profile_file

	profiles="${LAUNCHLAYER_PROFILES:-${STEAM_LAUNCH_PROFILES:-}}"
	if [[ -z "$profiles" && -n "${LAUNCHLAYER_PROFILE:-${STEAM_LAUNCH_PROFILE:-}}" ]]; then
		profiles="${LAUNCHLAYER_PROFILE:-${STEAM_LAUNCH_PROFILE:-}}"
	fi
	if [[ -z "$profiles" ]]; then
		profiles="$(detect_default_profiles 2>/dev/null || true)"
	fi
	[[ -n "$profiles" ]] || return 0

	profiles="${profiles//,/ }"
	for profile in $profiles; do
		profile_file="$PROFILES_DIR/${profile}.env"
		if [[ -f "$profile_file" ]]; then
			debug "loaded profile: $profile"
			load_config_file "$profile_file" 0
		fi
	done
}

# load_launch_config — Build the effective config for the current launch.
load_launch_config() {
	config_loaded=()
	config_key_sources=()
	config_layers=()
	load_profile_config
	load_config_file "$LAUNCHD_DIR/default.env" 0
	if [[ -f "$LAUNCHD_DIR/local.env" ]]; then
		load_config_file "$LAUNCHD_DIR/local.env" 1
	fi

	if [[ -z "$steam_app_id" ]]; then
		return 0
	fi

	local appid_env
	appid_env="$(resolve_appid_env_path "$steam_app_id")"
	if [[ -f "$appid_env" ]]; then
		# Per-game file overrides preset selection entirely.
		load_config_file "$appid_env" 1
	elif detect_native_game "$steam_app_id"; then
		debug "auto-selected preset: native"
		load_config_file "$LAUNCHD_DIR/presets/native.env" 0
	else
		debug "auto-selected preset: standard"
		load_config_file "$LAUNCHD_DIR/presets/standard.env" 0
	fi
}

# apply_defaults — Set fallback values for every tunable knob.
#
# Uses bash parameter expansion (: "${VAR:=default}") so explicit exports
# from .env files are never clobbered.
apply_defaults() {
	: "${BENCHMARK:=0}"
	: "${GAMEMODE:=1}"
	: "${MANGOHUD:=0}"
	: "${MANGOHUD_LOG:=0}"
	: "${NETWORK_TUNE:=0}"
	: "${DEBUG:=0}"
	: "${X3D_CPUS:=}"
	: "${GAME_NIC:=}"
	: "${GAMESCOPE:=0}"
	: "${GAMESCOPE_W:=}"
	: "${GAMESCOPE_H:=}"
	: "${GAMESCOPE_R:=}"
	# Empty/auto = detect VRR when Gamescope on; 0/1 force.
	: "${GAMESCOPE_ADAPTIVE_SYNC:=}"
	: "${GAMESCOPE_EXPOSE_WAYLAND:=0}"
	: "${GAMESCOPE_FSR:=0}"
	: "${GAMESCOPE_FSR_SHARPNESS:=5}"
	: "${GAMESCOPE_EXTRA_ARGS:=}"
	: "${GAMESCOPE_PREFER_OUTPUT:=}"
	: "${GAMESCOPE_FRAME_LIMIT:=}"
	: "${GAMESCOPE_FILTER:=}"
	: "${GAMESCOPE_FOCUSED_FPS:=}"
	: "${GAMESCOPE_UNFOCUSED_FPS:=}"
	: "${GAMESCOPE_NESTED_FIX:=1}"
	: "${SHADER_CACHE_CHECK:=1}"
	: "${SHADER_CACHE_MAX_GB:=10}"
	: "${SHADER_CACHE_TRIM:=0}"
	: "${SHADER_CACHE_CHECK_INTERVAL_HOURS:=24}"
	: "${SHADER_CACHE_BOOST:=0}"
	: "${SHADER_CACHE_BOOST_GB:=12}"
	: "${COMPATDATA_CHECK:=1}"
	: "${COMPATDATA_MAX_GB:=50}"
	: "${COMPATDATA_TRIM:=0}"
	: "${VM_MAX_MAP_COUNT_MIN:=$LAUNCHLAYER_VM_MAX_MAP_COUNT_DEFAULT}"
	: "${VM_MAX_MAP_COUNT_FIX:=0}"
	: "${VRAM_HOG_UNITS:=hyprwhspr.service app-dev.lizardbyte.app.Sunshine.service}"
	: "${VRAM_HOG_PIDS:=}"
	: "${VRAM_HOGS:=0}"
	: "${LAUNCH_WATCHDOG:=1}"
	: "${LAUNCH_WRAPPERS:=}"
	: "${LAUNCH_WRAPPERS_BEFORE:=}"
	: "${GAME_EXTRA_ARGS:=}"
	: "${UNSET_VARS:=}"
	: "${FORCE_NATIVE:=0}"
	: "${FORCE_PROTON:=0}"
	: "${VRAM_PREFLIGHT_MIN_MB:=0}"
	: "${PIPEWIRE_LOW_LATENCY:=0}"
	: "${LAUNCH_LOG_MAX_LINES:=5000}"
	: "${PRE_LAUNCH_CMD:=}"
	: "${POST_LAUNCH_CMD:=}"
	: "${DISK_PREFLIGHT_MIN_GB:=0}"
	: "${GPU_POWER_CHECK:=0}"
	: "${NVIDIA_POWER_MODE:=0}"
	: "${CONCURRENT_LAUNCH_GUARD:=1}"
	: "${GPU_VRAM_PROCESS_MIN_MB:=0}"
	: "${DISABLE_CPU_AFFINITY:=0}"
	: "${GAME_PERFORMANCE:=1}"
	: "${CPU_AFFINITY_RANGE:=}"
	: "${DISABLE_NIC_EEE:=1}"
	: "${DISABLE_WIFI_POWER_SAVE:=1}"
	: "${MALLOC_ALLOCATOR:=}"
	: "${ENABLE_HDR:=}"
	: "${GAMESCOPE_HDR:=0}"
	: "${DISK_TUNE:=0}"
	: "${OVERRIDE_PROTON:=}"
	# 0=off, 1=dlss-swapper (NGX updater + latest preset), dll=dlss-swapper-dll (presets only)
	: "${DLSS_SWAPPER:=0}"
	# Proton-CachyOS / GE / EM upscaler DLL upgrades (not Valve Proton).
	: "${PROTON_DLSS_UPGRADE:=0}"
	: "${PROTON_DLSS_INDICATOR:=0}"
	: "${PROTON_FSR4_UPGRADE:=0}"
	: "${PROTON_FSR4_RDNA3_UPGRADE:=0}"
	: "${PROTON_FSR4_INDICATOR:=0}"
	: "${PROTON_XESS_UPGRADE:=0}"
	: "${PROTON_NVIDIA_LIBS:=0}"
	: "${PROTON_NVIDIA_LIBS_NO_32BIT:=0}"
	# Arch Gaming wiki: eager symbol resolve, post-process layers, DRI latency.
	: "${LD_BIND_NOW:=0}"
	: "${VKBASALT:=0}"
	: "${VKBASALT_CONFIG_FILE:=}"
	: "${VKBASALT_LOG_LEVEL:=}"
	: "${LATENCYFLEX:=0}"
	: "${DISABLE_VBLANK:=0}"
	# Bazzite: SteamDeck=0 (sd0) and DXVK/VKD3D frame limiters.
	: "${DISABLE_STEAM_DECK:=0}"
	: "${FRAME_RATE:=}"
	# Extended first-party tools (see docs/third-party.md for licenses).
	: "${LSFG_VK:=0}"
	: "${LSFG_PROCESS:=}"
	: "${LSFG_CONFIG_FILE:=}"
	: "${OBS_VKCAPTURE:=0}"
	: "${DISCORD_IPC:=0}"
	: "${REPLAY_CAPTURE:=0}"
	: "${REPLAY_TOOL:=auto}"
	: "${BLOCK_INTERNET:=0}"
	: "${CONTY:=0}"
	: "${CONTY_PATH:=}"
	: "${WINETRICKS_VERBS:=}"
	: "${WINETRICKS_GUI:=0}"
	: "${WINECFG_BEFORE:=0}"
	: "${REGISTRY_FILES:=}"
	: "${WINE_FSR:=0}"
	: "${WINE_FSR_STRENGTH:=}"
	: "${WINE_FSR_MODE:=}"
	: "${SPECIAL_K:=0}"
	: "${SPECIAL_K_DLL:=dxgi}"
	: "${SPECIAL_K_SOURCE:=}"
	: "${SPECIAL_K_INI:=}"
	: "${SPECIAL_K_FETCH:=0}"
	: "${SPECIAL_K_FETCH_URL:=}"
	: "${SPECIAL_K_VERSION:=stable}"
	: "${RESHADE:=0}"
	: "${RESHADE_DLL:=dxgi}"
	: "${RESHADE_SOURCE:=}"
	: "${RESHADE_SK_VERSION:=}"
	: "${DEPTH3D:=0}"
	: "${DEPTH3D_SOURCE:=}"
	: "${DEPTH3D_FETCH_URL:=}"
	: "${SKIF:=0}"
	: "${SKIF_PATH:=}"
	: "${SKIF_LAUNCH:=0}"
	: "${VALVEPLUG:=0}"
	: "${VALVEPLUG_SOURCE:=}"
	: "${VALVEPLUG_STEAM_DIR:=}"
	: "${FLAWLESS_WIDESCREEN:=0}"
	: "${FWS:=0}"
	: "${FWS_PATH:=}"
	: "${FWS_COLAUNCH:=1}"
	: "${SPECIALTY_RUNTIME:=}"
	: "${OPENVR_FSR:=0}"
	: "${OPENVR_FSR_SOURCE:=}"
	: "${GEO11:=0}"
	: "${GEO11_SOURCE:=}"
	: "${GEO11_SBS_VR:=0}"
	: "${SBS_VR:=0}"
	: "${SBS_VR_PLAYER:=}"
	: "${SBS_VR_REQUIRE_HMD:=1}"
	: "${FLAT2VR:=0}"
	: "${FLAT2VR_SOURCE:=}"
	: "${PLAYTIME_LOG:=0}"
	: "${CRASH_GUESS:=0}"
	: "${CRASH_GUESS_TIMEOUT:=0}"
	: "${INJECT_SHA256:=}"
}

# config_file_display_name — Parse game name from scaffold header, or fall back to AppID.
config_file_display_name() {
	local file=$1 appid=$2 line=""
	[[ -f "$file" ]] || {
		echo "AppID $appid"
		return 0
	}
	line="$(head -n1 "$file" 2>/dev/null || true)"
	if [[ "$line" =~ ^#[[:space:]]*(.+)[[:space:]]+\(Steam[[:space:]]AppID[[:space:]]+[0-9]+ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo "AppID $appid"
	fi
}

# collect_managed_config_files — Relative paths under CONFIG_DIR for export/import bundles.
collect_managed_config_files() {
	local include_local=${1:-0} include_profiles=${2:-1}
	local -n _files=$3
	local file base

	_files=()
	[[ -f "$LAUNCHD_DIR/default.env" ]] && _files+=("launch.d/default.env")
	if [[ "$include_local" == "1" && -f "$LAUNCHD_DIR/local.env" ]]; then
		_files+=("launch.d/local.env")
	fi
	if [[ "$include_profiles" == "1" ]]; then
		for file in "$LAUNCHD_DIR"/profiles/*.env; do
			[[ -f "$file" ]] || continue
			_files+=("launch.d/profiles/$(basename "$file")")
		done
	fi
	for file in "$LAUNCHD_DIR"/presets/*.env; do
		[[ -f "$file" ]] || continue
		_files+=("launch.d/presets/$(basename "$file")")
	done
	for file in "$GAMES_DIR"/[0-9]*.env; do
		[[ -f "$file" ]] || continue
		_files+=("games/$(basename "$file")")
	done
	for base in anticheat-appids.txt native-appids.txt; do
		[[ -f "$LAUNCHD_DIR/$base" ]] && _files+=("launch.d/$base")
	done
}

# config_file_abs_from_rel — Map manifest-relative path to absolute file path.
config_file_abs_from_rel() {
	local rel=$1
	case "$rel" in
		games/*)
			printf '%s/%s\n' "$GAMES_DIR" "$(basename "$rel")"
			;;
		*)
			printf '%s/%s\n' "$CONFIG_DIR" "$rel"
			;;
	esac
}

# write_appid_env_scaffold — Create per-game config from a preset name.
write_appid_env_scaffold() {
	local appid=$1 name=$2 preset=$3 path=${4:-}
	[[ -n "$path" ]] || path="$(appid_env_write_path "$appid")"
	mkdir -p "$(dirname "$path")"
	cat > "$path" <<EOF
# $name (Steam AppID $appid)
INCLUDE=presets/${preset}.env

EOF
}
