# shellcheck shell=bash
# lib/tui/config.sh — Per-game .env helpers and override management.

[[ -n "${LAUNCHLAYER_TUI_LOADED:-}" ]] && return 0
LAUNCHLAYER_TUI_LOADED=1
TUI_PRESETS=(standard competitive lightweight native)
TUI_GAME_FILTERS=(all configured unconfigured)
TUI_PRESS_ENTER_LINES=${TUI_PRESS_ENTER_LINES:-8}
# Plain assignment (not declare -a): TUI modules load via launchlayer_source_tui(),
# and declare from a function-sourced file stays function-local in bash.
TUI_CRUMB_STACK=()

# tui_json_enabled — True when TUI view commands should use --json output.
tui_json_enabled() {
	[[ "${TUI_JSON_OUTPUT:-0}" == "1" ]]
}

# tui_json_flag — Return 1 or 0 for command json arguments.
tui_json_flag() {
	if tui_json_enabled; then
		printf '1'
	else
		printf '0'
	fi
}

# Per-game editor surfaces are derived from the canonical config-key metadata.
TUI_TOGGLE_KEYS=()
TUI_ADVANCED_KEYS=()
for _tui_key in "${LAUNCHLAYER_CONFIG_KEYS[@]}"; do
	case "$(config_key_tui_surface "$_tui_key")" in
		toggle) TUI_TOGGLE_KEYS+=("$_tui_key") ;;
		advanced) TUI_ADVANCED_KEYS+=("$_tui_key") ;;
		both)
			TUI_TOGGLE_KEYS+=("$_tui_key")
			TUI_ADVANCED_KEYS+=("$_tui_key")
			;;
	esac
done
unset _tui_key

# Keys that are path/env assist only (no first-party inject) — labeled in toggle rows.
TUI_ASSIST_ONLY_KEYS=(
	DEPTH3D GEO11 GEO11_SBS_VR SBS_VR FLAT2VR
)

# Compact preview: always show these toggles, plus any per-game overrides.
TUI_PREVIEW_HOT_KEYS=(
	GAMEMODE MANGOHUD GAMESCOPE DLSS_SWAPPER SPECIAL_K RESHADE LSFG_VK
	OBS_VKCAPTURE CONTY BLOCK_INTERNET PLAYTIME_LOG CRASH_GUESS
)

# tui_appid_env_path — Preferred write path for per-game configs (GAMES_DIR).
tui_appid_env_path() {
	appid_env_write_path "$1"
}

# tui_ensure_appid_env — Create per-game config from suggested preset when missing.
tui_ensure_appid_env() {
	local appid=$1
	appid_env_exists "$appid" && return 0
	tui_run_side_effect init_appid_config "$appid" "" 0
}

# tui_env_file_get — Read KEY=value from a .env file (last match wins).
tui_env_file_get() {
	local file=$1 key=$2
	grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-
}

# tui_env_upsert — Compatibility name for the shared per-game config writer.
tui_env_upsert() {
	appid_env_upsert "$@"
}

# tui_effective_key — Return effective value for a config key after loading layers.
tui_effective_key() {
	local appid=$1 key=$2
	prepare_launch_context "$appid"
	printf '%s' "${!key-}"
}

# tui_assist_only_key_p — True when key is path/env assist (no first-party inject).
tui_assist_only_key_p() {
	local key=$1 k
	for k in "${TUI_ASSIST_ONLY_KEYS[@]}"; do
		[[ "$k" == "$key" ]] && return 0
	done
	return 1
}

# tui_toggle_game_key — Flip a boolean-ish key (DLSS_SWAPPER cycles 0→1→dll→0).
tui_toggle_game_key() {
	local appid=$1 key=$2 effective new_val file
	tui_ensure_appid_env "$appid"
	file="$(tui_appid_env_path "$appid")"
	effective="$(tui_effective_key "$appid" "$key")"
	if [[ "$key" == DLSS_SWAPPER ]]; then
		case "${effective,,}" in
			1|yes|true|on) new_val=dll ;;
			dll) new_val=0 ;;
			*) new_val=1 ;;
		esac
	else
		case "$effective" in
			1|yes|true|on|YES|TRUE|ON) new_val=0 ;;
			*) new_val=1 ;;
		esac
	fi
	tui_env_upsert "$file" "$key" "$new_val"
	# Prefer FLAWLESS_WIDESCREEN in the UI; keep alias FWS from drifting opposite.
	if [[ "$key" == FLAWLESS_WIDESCREEN ]]; then
		tui_env_upsert "$file" FWS "$new_val"
	fi
	tui_panel_note "Set $key=$new_val in $(basename "$file") (was: ${effective:-unset})" "Toggle"
}

# tui_validate_game_config_brief — One-line validation hint after per-game edits.
tui_validate_game_config_brief() {
	local appid=$1 file
	file="$(tui_appid_env_path "$appid")"
	[[ -f "$file" ]] || return 0
	if ! validate_single_config_file "$file" >/dev/null 2>&1; then
		tui_panel_note "validation: issues in $(basename "$file") — use [Manage] Validate" "Validation"
	fi
}

# tui_set_include_preset — Point per-game INCLUDE= at a named preset.
tui_set_include_preset() {
	tui_run_side_effect set_include_preset "$1" "$2"
}

# tui_prompt_env_key — Prompt for a string key and write to per-game .env.
# Empty keeps the current value; enter "-" to clear.
tui_prompt_env_key() {
	local appid=$1 key=$2 prompt=$3
	local file current new_val
	tui_ensure_appid_env "$appid"
	file="$(tui_appid_env_path "$appid")"
	current="$(tui_env_file_get "$file" "$key")"
	[[ -z "$current" ]] && current="$(tui_effective_key "$appid" "$key")"
	read -r -p "${prompt} [${current:-empty}; - clears]: " new_val </dev/tty || return 1
	if [[ "$new_val" == "-" ]]; then
		new_val=""
	elif [[ -z "$new_val" ]]; then
		new_val="$current"
	fi
	tui_env_upsert "$file" "$key" "$new_val"
	tui_panel_note "Set $key=${new_val:-<empty>}" "Config"
}

# tui_advanced_key_prompt — Human prompt for an advanced config key.
tui_advanced_key_prompt() {
	case "$1" in
		OVERRIDE_PROTON) printf '%s' "Compat tool (e.g. proton-cachyos-slr, GE-Proton10-34)" ;;
		DLSS_SWAPPER) printf '%s' "DLSS wrapper: 0 | 1 (NGX) | dll (presets only)" ;;
		FRAME_RATE) printf '%s' "DXVK/VKD3D FPS cap (blank/0 = off)" ;;
		ENABLE_HDR) printf '%s' "HDR: empty=auto | 0=off | 1=on" ;;
		MALLOC_ALLOCATOR) printf '%s' "Allocator: empty | jemalloc | mimalloc" ;;
		GAMESCOPE_W) printf '%s' "Gamescope width" ;;
		GAMESCOPE_H) printf '%s' "Gamescope height" ;;
		GAMESCOPE_R) printf '%s' "Gamescope refresh Hz" ;;
		GAMESCOPE_FSR_SHARPNESS) printf '%s' "Gamescope FSR sharpness (0-20)" ;;
		GAMESCOPE_EXTRA_ARGS) printf '%s' "Extra gamescope argv (before --)" ;;
		GAMESCOPE_PREFER_OUTPUT) printf '%s' "Gamescope -O / prefer-output" ;;
		GAMESCOPE_FRAME_LIMIT) printf '%s' "Gamescope --framerate-limit" ;;
		GAMESCOPE_FILTER) printf '%s' "Gamescope --filter — picker (fsr|nis|linear|…)" ;;
		GAMESCOPE_RESHADE_EFFECT) printf '%s' "Gamescope ReShade effect filename" ;;
		GAMESCOPE_RESHADE_TECHNIQUE) printf '%s' "Gamescope ReShade technique index" ;;
		GAMESCOPE_FOCUSED_FPS) printf '%s' "Gamescope focused FPS limit" ;;
		GAMESCOPE_UNFOCUSED_FPS) printf '%s' "Gamescope unfocused FPS limit" ;;
		VKBASALT_CONFIG_FILE) printf '%s' "vkBasalt config file path" ;;
		VKBASALT_LOG_LEVEL) printf '%s' "vkBasalt log level" ;;
		LSFG_PROCESS) printf '%s' "lsfg-vk LSFG_PROCESS profile" ;;
		LSFG_CONFIG_FILE) printf '%s' "lsfg-vk config path" ;;
		REPLAY_TOOL) printf '%s' "replay: auto|gpu-screen-recorder|replay-sorcery (picker)" ;;
		WINETRICKS_VERBS) printf '%s' "protontricks verbs (space-separated)" ;;
		REGISTRY_FILES) printf '%s' ".reg files to apply (space-separated)" ;;
		WINE_FSR_STRENGTH) printf '%s' "WINE_FULLSCREEN_FSR_STRENGTH" ;;
		WINE_FSR_MODE) printf '%s' "WINE_FULLSCREEN_FSR_MODE" ;;
		SPECIAL_K_DLL) printf '%s' "Special K proxy DLL name (dxgi|d3d11|…)" ;;
		SPECIAL_K_SOURCE) printf '%s' "Dir with SpecialK32/64.dll" ;;
		SPECIAL_K_INI) printf '%s' "Special K INI path (UsingWINE)" ;;
		SPECIAL_K_FETCH_URL) printf '%s' "Optional Special K download URL" ;;
		SPECIAL_K_VERSION) printf '%s' "Special K cache version label" ;;
		RESHADE_DLL) printf '%s' "ReShade proxy DLL name" ;;
		RESHADE_SOURCE) printf '%s' "Dir with ReShade DLL" ;;
		RESHADE_SK_VERSION) printf '%s' "ReShade version pin for SK cohab" ;;
		OPTISCALER_SOURCE) printf '%s' "Dir or file containing OptiScaler.dll/OptiScaler.asi" ;;
		OPTISCALER_PROXY) printf '%s' "OptiScaler proxy filename — picker" ;;
		OPTISCALER_CONFIG) printf '%s' "OptiScaler.ini source path" ;;
		DEPTH3D_SOURCE) printf '%s' "Depth3D shader directory (assist-only)" ;;
		DEPTH3D_FETCH_URL) printf '%s' "Optional Depth3D archive URL (user-supplied)" ;;
		SKIF_PATH) printf '%s' "Path to SKIF.exe" ;;
		VALVEPLUG_SOURCE) printf '%s' "Dir with ValvePlug XInput1_4.dll" ;;
		VALVEPLUG_STEAM_DIR) printf '%s' "Windows Steam client dir for ValvePlug" ;;
		FWS_PATH) printf '%s' "FlawlessWidescreen executable path" ;;
		FWS) printf '%s' "Alias of FLAWLESS_WIDESCREEN (prefer long name in Quick toggles)" ;;
		CONTY_PATH) printf '%s' "Conty binary path" ;;
		SPECIALTY_RUNTIME) printf '%s' "boxtron|luxtorpeda|roberta|(clear) — picker" ;;
		OPENVR_FSR_SOURCE) printf '%s' "OpenVR-FSR files directory" ;;
		OPENCOMPOSITE_SOURCE) printf '%s' "OpenComposite files directory" ;;
		GEO11_SOURCE) printf '%s' "Geo11 directory (assist-only)" ;;
		SBS_VR_PLAYER) printf '%s' "SBS VR player hint (assist-only)" ;;
		FLAT2VR_SOURCE) printf '%s' "Flat2VR directory (assist-only)" ;;
		CRASH_GUESS_TIMEOUT) printf '%s' "Crash-guess seconds (0 with CRASH_GUESS=1 → default 5)" ;;
		INJECT_SHA256) printf '%s' "Required SHA256 for remote inject downloads" ;;
		GAMESCOPE_ADAPTIVE_SYNC) printf '%s' "VRR: empty(auto)|auto|0|1 — picker" ;;
		SHADER_CACHE_MAX_GB) printf '%s' "Shader cache max GB" ;;
		SHADER_CACHE_BOOST_GB) printf '%s' "Shader cache boost size GB" ;;
		SHADER_CACHE_CHECK_INTERVAL_HOURS) printf '%s' "Shader cache check interval (hours)" ;;
		COMPATDATA_MAX_GB) printf '%s' "Compatdata max GB" ;;
		VM_MAX_MAP_COUNT_MIN) printf '%s' "vm.max_map_count minimum" ;;
		X3D_CPUS) printf '%s' "X3D CCD CPU list (e.g. 0-7)" ;;
		CPU_AFFINITY_RANGE) printf '%s' "taskset CPU range" ;;
		GAME_NIC) printf '%s' "Network interface for NETWORK_TUNE" ;;
		GPU_SELECT) printf '%s' "GPU selection: auto|discrete|nvidia|amd|intel — picker" ;;
		GPU_SELECT_DRIVER) printf '%s' "Vulkan loader driver-name filter" ;;
		VRAM_HOG_UNITS) printf '%s' "VRAM-hog systemd user units (space-separated)" ;;
		VRAM_HOG_PIDS) printf '%s' "VRAM-hog PIDs (space-separated)" ;;
		VRAM_PREFLIGHT_MIN_MB) printf '%s' "VRAM preflight minimum MB" ;;
		DISK_PREFLIGHT_MIN_GB) printf '%s' "Disk free-space preflight GB" ;;
		GPU_VRAM_PROCESS_MIN_MB) printf '%s' "Warn if other GPU processes exceed MB" ;;
		MANGOHUD_CONFIG) printf '%s' "MangoHUD config string" ;;
		MANGOHUD_CONFIGFILE) printf '%s' "MangoHUD config file path" ;;
		PRE_LAUNCH_CMD) printf '%s' "Command before launch (local only)" ;;
		POST_LAUNCH_CMD) printf '%s' "Command after launch (local only)" ;;
		LAUNCH_LOG_MAX_LINES) printf '%s' "launch.log max lines" ;;
		GAME_EXTRA_ARGS) printf '%s' "Game CLI args" ;;
		LAUNCH_WRAPPERS) printf '%s' "Wrappers after game-performance/DLSS" ;;
		LAUNCH_WRAPPERS_BEFORE) printf '%s' "Wrappers before gamemoderun" ;;
		UNSET_VARS) printf '%s' "Space-separated vars to unset" ;;
		*) printf '%s' "Value for $1" ;;
	esac
}

# tui_edit_advanced_key — Prompt (or picker) and validate one advanced key for an appid.
tui_edit_advanced_key() {
	local appid=$1 key=$2 picked file
	case "$key" in
		SPECIALTY_RUNTIME|REPLAY_TOOL|GAMESCOPE_FILTER|GAMESCOPE_ADAPTIVE_SYNC|DLSS_SWAPPER|GPU_SELECT|OPTISCALER_PROXY)
			picked="$(tui_pick_enum_key "$key")" || return 0
			tui_ensure_appid_env "$appid"
			file="$(tui_appid_env_path "$appid")"
			tui_env_upsert "$file" "$key" "$picked"
			tui_panel_note "Set $key=${picked:-<empty>}" "Config"
			tui_validate_game_config_brief "$appid"
			return 0
			;;
		FWS)
			# Keep alias in sync with the preferred long name when editing from Advanced.
			tui_prompt_env_key "$appid" "$key" "$(tui_advanced_key_prompt "$key")"
			file="$(tui_appid_env_path "$appid")"
			picked="$(tui_env_file_get "$file" FWS)"
			tui_env_upsert "$file" FLAWLESS_WIDESCREEN "${picked:-0}"
			tui_validate_game_config_brief "$appid"
			return 0
			;;
	esac
	tui_prompt_env_key "$appid" "$key" "$(tui_advanced_key_prompt "$key")"
	tui_validate_game_config_brief "$appid"
}

# tui_open_in_editor — Open a config file in \$EDITOR.
tui_open_in_editor() {
	local path=$1 editor
	editor="${EDITOR:-${VISUAL:-nano}}"
	[[ -f "$path" ]] || {
		tui_show_text "File not found: $path" "Editor"
		return 1
	}
	"$editor" "$path"
}

# tui_open_or_create_in_editor — Open a config file, creating an empty file when missing.
tui_open_or_create_in_editor() {
	local path=$1
	if [[ ! -f "$path" ]]; then
		mkdir -p "$(dirname "$path")"
		touch "$path"
		tui_panel_note "Created $path" "Editor"
	fi
	tui_open_in_editor "$path"
}

# tui_env_remove_key — Remove KEY= lines from a per-game .env file.
tui_env_remove_key() {
	local file=$1 key=$2
	local tmp found=0 line
	[[ -f "$file" ]] || return 1
	tmp="$(mktemp)"
	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^[[:space:]]*${key}= ]]; then
			found=1
			continue
		fi
		printf '%s\n' "$line"
	done < "$file" > "$tmp"
	if (( ! found )); then
		rm -f "$tmp"
		return 1
	fi
	mv "$tmp" "$file"
	return 0
}

# tui_game_override_keys — List keys explicitly set in a per-game .env file.
tui_game_override_keys() {
	local appid=$1 file
	file="$(tui_appid_env_path "$appid")"
	[[ -f "$file" ]] || return 0
	grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$file" 2>/dev/null \
		| sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=.*/\1/' \
		| sort -u
}

# tui_clear_game_key_override — Drop a per-game override so layers inherit again.
tui_clear_game_key_override() {
	local appid=$1 key=$2 file effective
	file="$(tui_appid_env_path "$appid")"
	if tui_env_remove_key "$file" "$key"; then
		effective="$(tui_effective_key "$appid" "$key")"
		tui_panel_note "Cleared $key override in $(basename "$file") (now inherits: ${effective:-unset})" "Override"
		return 0
	fi
	tui_panel_note "No override for $key in $(basename "$file")" "Override"
	return 1
}

# tui_clear_all_game_overrides — Remove every per-game override key.
tui_clear_all_game_overrides() {
	local appid=$1 file key -a keys=()
	file="$(tui_appid_env_path "$appid")"
	mapfile -t keys < <(tui_game_override_keys "$appid")
	((${#keys[@]})) || {
		tui_panel_note "No per-game overrides in $(basename "$file")" "Override"
		return 0
	}
	tui_confirm "Clear all ${#keys[@]} override(s) in $(basename "$file")?" || return 0
	for key in "${keys[@]}"; do
		tui_env_remove_key "$file" "$key"
	done
	tui_panel_note "Cleared ${#keys[@]} override(s) — all keys now inherit from layers" "Override"
	tui_validate_game_config_brief "$appid"
}

# tui_game_validation_label — Short validation summary for game action headers.
tui_game_validation_label() {
	local appid=$1 file
	file="$(tui_appid_env_path "$appid")"
	[[ -f "$file" ]] || {
		printf 'inherits layers'
		return 0
	}
	if validate_single_config_file "$file" >/dev/null 2>&1; then
		printf '%s ok' "$(tui_glyph_ok)"
	else
		printf '%s issues' "$(tui_glyph_bad)"
	fi
}

# tui_edit_appid_config — Open per-game .env in \$EDITOR; scaffold when missing.
tui_edit_appid_config() {
	local appid=$1 path
	[[ -n "$appid" ]] || return 1
	if ! appid_env_exists "$appid"; then
		tui_run_paged init_appid_config "$appid" "" 0 || return 1
	fi
	path="$(resolve_appid_env_path "$appid")"
	tui_open_in_editor "$path"
}

# tui_build_recent_picker_lines — Recent games only (from launch.log).
tui_build_recent_picker_lines() {
	local -a all_lines=() recent_ids=() line appid
	local -a recent_lines=()
	tui_games_cache_start
	if tui_games_cache_ready; then
		mapfile -t all_lines < <(tui_games_cache_lines)
	else
		mapfile -t all_lines < <(tui_games_cache_wait && tui_games_cache_lines)
	fi
	mapfile -t recent_ids < <(tui_recent_game_appids 12)
	for appid in "${recent_ids[@]}"; do
		for line in "${all_lines[@]}"; do
			[[ "${line%% *}" == "$appid" ]] || continue
			recent_lines+=("$(tui_format_game_picker_row "$line" 1)")
			break
		done
	done
	((${#recent_lines[@]})) || return 1
	tui_game_list_column_header
	printf '%s\n' "${recent_lines[@]}"
}

# tui_pick_recent_game_appid — Select from recent games only; prints AppID.
tui_pick_recent_game_appid() {
	local line appid header
	local -a lines=()
	header="Recent games (from launch.log)"
	mapfile -t lines < <(tui_build_recent_picker_lines)
	((${#lines[@]} > 1)) || {
		tui_show_text "No recent games in launch.log — launch a game through LaunchLayer first." "Recent games"
		return 1
	}
	if tui_has_fzf; then
		line="$(printf '%s\n' "${lines[@]}" | tui_fzf_run_stdin single "$header" game)" || return 1
	else
		line="$(tui_select_pick "$header" "${lines[@]:1}")" || return 1
	fi
	appid="$(tui_parse_game_picker_line "$line")"
	[[ "$appid" =~ ^[0-9]+$ ]] || return 1
	printf '%s\n' "$appid"
}

# tui_recent_games_menu — Jump straight to a recently played title.
tui_recent_games_menu() {
	local appid
	appid="$(tui_pick_recent_game_appid)" || return 0
	tui_game_actions "$appid"
}

# tui_clear_override_menu — Pick and remove a per-game override key.
tui_clear_override_menu() {
	local appid=$1 key -a keys=()
	mapfile -t keys < <(tui_game_override_keys "$appid")
	((${#keys[@]})) || {
		tui_panel_note "No per-game overrides in $(basename "$(tui_appid_env_path "$appid")")" "Override"
		return 0
	}
	key="$(tui_menu "Pick key to clear" \
		"Clear ALL overrides" \
		"${keys[@]}")" || return 0
	if [[ "$key" == "Clear ALL overrides" ]]; then
		tui_clear_all_game_overrides "$appid"
		return 0
	fi
	tui_clear_game_key_override "$appid" "$key"
	tui_validate_game_config_brief "$appid"
}
