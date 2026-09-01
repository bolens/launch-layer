# shellcheck shell=bash
# lib/tui/menus-game.sh — Game browse, toggles, and per-title actions.
# ---------------------------------------------------------------------------
# Configuration menus
# ---------------------------------------------------------------------------

# tui_games_hub_menu_select_fallback — Numbered games hub when fzf is unavailable.
tui_games_hub_menu_select_fallback() {
	local -a items=() choice
	mapfile -t items < <(tui_games_menu_print_items)
	choice="$(tui_select_pick "$(tui_crumb_label "(filter: ${TUI_GAME_FILTER:-all})")" "${items[@]}")" || return 1
	[[ -n "$choice" ]] || return 1
	if tui_games_menu_item_loading_p "$choice"; then
		tui_games_cache_wait || return 1
		choice="$(tui_games_menu_normalize_selection "$choice")"
	else
		choice="$(tui_games_menu_normalize_selection "$choice")"
	fi
	printf '%s\n' "$choice"
}

# tui_format_toggle_option — Menu line using already-loaded effective settings.
tui_format_toggle_option() {
	local appid=$1 key=$2 effective override file label suffix value_note
	file="$(tui_appid_env_path "$appid")"
	effective="${!key-}"
	override=""
	[[ -f "$file" ]] && override="$(tui_env_file_get "$file" "$key")"
	suffix=""
	tui_assist_only_key_p "$key" && suffix=" assist"
	value_note=""
	[[ "$key" == DLSS_SWAPPER && "${effective,,}" == dll ]] && value_note="=dll"
	if [[ -n "$override" ]]; then
		if cli_uses_color; then
			label="$(printf '%s%s %s' "$key" "$value_note" "$(tui_glyph_bool_onoff "$effective")")"
			printf '%s  %s%s' "$label" "$(cli_dim override)" "$(cli_dim "$suffix")"
		else
			printf '%s%s=%s  (override)%s' "$key" "$value_note" "$(tui_glyph_bool_onoff "$effective")" "$suffix"
		fi
	else
		if cli_uses_color; then
			printf '%s%s  %s  %s%s' "$key" "$value_note" "$(tui_glyph_bool_onoff "$effective" 1)" "$(cli_dim inherited)" "$(cli_dim "$suffix")"
		else
			printf '%s%s=%s  (inherited)%s' "$key" "$value_note" "$(tui_glyph_bool_onoff "$effective")" "$suffix"
		fi
	fi
}

# tui_quick_toggles_reload — Print quick-toggle rows for fzf reload (stdout).
tui_quick_toggles_reload() {
	local appid=$1 key
	tui_ensure_appid_env "$appid"
	prepare_launch_context "$appid"
	for key in "${TUI_TOGGLE_KEYS[@]}"; do
		printf '%s\n' "$(tui_format_toggle_option "$appid" "$key")"
	done
	printf '%s\n' \
		"Clear override (inherit from layers)" \
		"Clear ALL overrides" \
		"Back"
}

# tui_quick_toggles_flip — Flip one toggle key from a menu row (fzf execute-silent).
tui_quick_toggles_flip() {
	local appid=$1 selection=$2 key
	selection="$(printf '%s' "$selection" | tui_strip_ansi)"
	key="$(tui_toggle_key_from_option "$selection")"
	[[ -n "$key" ]] || return 0
	tui_ensure_appid_env "$appid"
	tui_toggle_game_key "$appid" "$key"
	tui_validate_game_config_brief "$appid"
}

# tui_quick_toggles — Toggle boolean launch settings in per-game .env.
tui_quick_toggles() {
	local appid=$1 action key last_anchor="" -a options=()
	tui_ensure_appid_env "$appid"
	tui_crumb_enter "Quick toggles"

	while true; do
		prepare_launch_context "$appid"
		options=()
		for key in "${TUI_TOGGLE_KEYS[@]}"; do
			options+=("$(tui_format_toggle_option "$appid" "$key")")
		done
		options+=("Clear override (inherit from layers)")
		options+=("Clear ALL overrides")
		options+=("Back")

		tui_menu_set_start_pos "$last_anchor" "${options[@]}"
		if tui_has_fzf; then
			action="$(tui_fzf_toggle_pick "$appid" "Flip per-game override")" || {
				tui_crumb_leave
				return 0
			}
		else
			action="$(TUI_MENU_CONTEXT=toggles tui_menu "Flip per-game override" "${options[@]}")" || {
				tui_crumb_leave
				return 0
			}
		fi
		[[ "$action" == Back ]] && break
		if [[ "$action" == "Clear override (inherit from layers)" ]]; then
			tui_clear_override_menu "$appid"
			continue
		fi
		if [[ "$action" == "Clear ALL overrides" ]]; then
			tui_clear_all_game_overrides "$appid"
			continue
		fi
		key="$(tui_toggle_key_from_option "$action")"
		[[ -n "$key" ]] || continue
		last_anchor=$key
		tui_toggle_game_key "$appid" "$key"
		tui_validate_game_config_brief "$appid"
	done
	tui_crumb_leave
}

# tui_advanced_config — String/numeric keys and preset INCLUDE changes.
# Groups keep the menu short while covering every TUI_ADVANCED_KEYS entry.
tui_advanced_config() {
	local appid=$1 name preset action include_label
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"

	while true; do
		prepare_launch_context "$appid"
		include_label="${INCLUDE:-auto}"
		TUI_MENU_CONTEXT=advanced
		action="$(tui_menu "Advanced config: $name (INCLUDE=${include_label})" \
			"Change INCLUDE preset" \
			"Proton & tools" \
			"Gamescope" \
			"Inject & Wine" \
			"Shader & storage" \
			"Affinity & network" \
			"VRAM & preflight" \
			"HUD & hooks" \
			"Wrappers & args" \
			"Back")" || return 0

		case "$action" in
			"Change INCLUDE preset")
				preset="$(tui_pick_preset)" || continue
				tui_set_include_preset "$appid" "$preset"
				tui_validate_game_config_brief "$appid"
				;;
			"Proton & tools")
				tui_advanced_config_group "$appid" "Proton & tools" \
					OVERRIDE_PROTON DLSS_SWAPPER FRAME_RATE ENABLE_HDR MALLOC_ALLOCATOR \
					SPECIALTY_RUNTIME
				;;
			"Gamescope")
				tui_advanced_config_group "$appid" "Gamescope" \
					GAMESCOPE_W GAMESCOPE_H GAMESCOPE_R GAMESCOPE_FSR_SHARPNESS GAMESCOPE_ADAPTIVE_SYNC \
					GAMESCOPE_EXTRA_ARGS GAMESCOPE_PREFER_OUTPUT GAMESCOPE_FRAME_LIMIT \
					GAMESCOPE_FILTER GAMESCOPE_RESHADE_EFFECT GAMESCOPE_RESHADE_TECHNIQUE \
					GAMESCOPE_FOCUSED_FPS GAMESCOPE_UNFOCUSED_FPS
				;;
			"Inject & Wine")
				tui_advanced_config_group "$appid" "Inject & Wine" \
					VKBASALT_CONFIG_FILE VKBASALT_LOG_LEVEL LSFG_PROCESS LSFG_CONFIG_FILE \
					WINETRICKS_VERBS REGISTRY_FILES WINE_FSR_STRENGTH WINE_FSR_MODE \
					SPECIAL_K_DLL SPECIAL_K_SOURCE SPECIAL_K_INI SPECIAL_K_FETCH_URL SPECIAL_K_VERSION \
					RESHADE_DLL RESHADE_SOURCE RESHADE_SK_VERSION DEPTH3D_SOURCE DEPTH3D_FETCH_URL \
					OPTISCALER_SOURCE OPTISCALER_PROXY OPTISCALER_CONFIG \
					FWS FWS_PATH CONTY_PATH OPENVR_FSR_SOURCE OPENCOMPOSITE_SOURCE GEO11_SOURCE \
					SBS_VR_PLAYER FLAT2VR_SOURCE SKIF_PATH \
					VALVEPLUG_SOURCE VALVEPLUG_STEAM_DIR INJECT_SHA256
				;;
			"Shader & storage")
				tui_advanced_config_group "$appid" "Shader & storage" \
					SHADER_CACHE_MAX_GB SHADER_CACHE_BOOST_GB SHADER_CACHE_CHECK_INTERVAL_HOURS \
					COMPATDATA_MAX_GB VM_MAX_MAP_COUNT_MIN
				;;
			"Affinity & network")
				tui_advanced_config_group "$appid" "Affinity & network" \
					X3D_CPUS CPU_AFFINITY_RANGE GAME_NIC GPU_SELECT GPU_SELECT_DRIVER
				;;
			"VRAM & preflight")
				tui_advanced_config_group "$appid" "VRAM & preflight" \
					VRAM_HOG_UNITS VRAM_HOG_PIDS VRAM_PREFLIGHT_MIN_MB \
					DISK_PREFLIGHT_MIN_GB GPU_VRAM_PROCESS_MIN_MB
				;;
			"HUD & hooks")
				tui_advanced_config_group "$appid" "HUD & hooks" \
					MANGOHUD_CONFIG MANGOHUD_CONFIGFILE \
					PRE_LAUNCH_CMD POST_LAUNCH_CMD LAUNCH_LOG_MAX_LINES REPLAY_TOOL CRASH_GUESS_TIMEOUT
				;;
			"Wrappers & args")
				tui_advanced_config_group "$appid" "Wrappers & args" \
					GAME_EXTRA_ARGS LAUNCH_WRAPPERS LAUNCH_WRAPPERS_BEFORE UNSET_VARS
				;;
			*) return 0 ;;
		esac
	done
}

# tui_advanced_config_group — Pick and edit keys within one advanced group.
tui_advanced_config_group() {
	local appid=$1 title=$2
	shift 2
	local -a keys=("$@")
	local -a items=()
	local key action
	for key in "${keys[@]}"; do
		items+=("Edit $key")
	done
	items+=("Back")

	while true; do
		TUI_MENU_CONTEXT=advanced
		action="$(tui_menu "Advanced › $title" "${items[@]}")" || return 0
		case "$action" in
			Back|"") return 0 ;;
			Edit\ *)
				key="${action#Edit }"
				tui_edit_advanced_key "$appid" "$key"
				;;
			*) return 0 ;;
		esac
	done
}

# tui_init_game_config — Scaffold or overwrite per-game config interactively.
tui_init_game_config() {
	local appid=$1 preset force=0 name
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"
	if [[ -f "$(tui_appid_env_path "$appid")" ]] || appid_env_exists "$appid"; then
		tui_confirm "Overwrite existing config for $name?" || return 0
		force=1
	fi
	preset="$(tui_pick_preset)" || return 0
	tui_run_paged init_appid_config "$appid" "$preset" "$force" || true
}

# tui_delete_game_config — Remove per-game .env after confirmation.
tui_delete_game_config() {
	local appid=$1 path
	path="$(resolve_appid_env_path "$appid")"
	[[ -f "$path" ]] || {
		tui_show_text "No per-game config at $path" "Delete config"
		return 0
	}
	if tui_confirm "Delete $(basename "$path")? (preset auto-selection will apply)"; then
		rm -f "$path"
		tui_show_text "Deleted $path" "Delete config"
	fi
}

# tui_show_dry_run — Print resolved launch chain without running a game.
tui_show_dry_run() {
	local appid=$1
	prepare_launch_context "$appid"
	print_dry_run /bin/true
}

# tui_suggest_config_menu — ProtonDB suggest preview / apply (parity with --suggest-config).
tui_suggest_config_menu() {
	local appid=$1 name action
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"

	action="$(tui_menu "ProtonDB suggestions: $name" \
		"Preview suggestions" \
		"Apply allowlisted knobs" \
		"Back")" || return 0

	case "$action" in
		"Preview suggestions")
			tui_run_paged suggest_config "$appid" 0 || true
			;;
		"Apply allowlisted knobs")
			tui_confirm "Apply ProtonDB allowlisted knobs to $name?" || return 0
			tui_run_capture "Fetching ProtonDB suggestions…" suggest_config "$appid" 1 || true
			;;
		*) return 0 ;;
	esac
}

# tui_game_actions — Action menu for one game.
tui_game_actions() {
	local appid=$1 name action status_label
	name="$(get_game_name "$appid" 2>/dev/null || echo "AppID $appid")"
	tui_crumb_enter "$name"

	while true; do
		status_label="$(tui_game_validation_label "$appid")"
		TUI_MENU_CONTEXT=actions
		TUI_ACTION_APPID=$appid
		action="$(tui_menu "Actions (${status_label})" \
			"[View] Resolved config" \
			"[View] Dry-run launch chain" \
			"[View] Paths (cache / install)" \
			"[View] Launch stats" \
			"[View] Runtime status" \
			"" \
			"[Edit] Quick toggles" \
			"[Edit] Advanced config" \
			"[Edit] Suggest from ProtonDB" \
			"[Edit] Clear override" \
			"[Edit] Open in \$EDITOR" \
			"[Edit] Set preset (re-init)" \
			"" \
			"[Manage] Validate config" \
			"[Manage] Delete per-game config" \
			"" \
			"[Hub] Community configs" \
			"" \
			"Back to games menu")" || {
			unset TUI_ACTION_APPID
			tui_crumb_leave
			return 0
		}
		unset TUI_ACTION_APPID

		[[ -n "$action" ]] || continue

		case "$action" in
			"[View] Resolved config")
				tui_run_paged show_config "$appid" "$(tui_json_flag)" || true
				;;
			"[View] Dry-run launch chain")
				tui_run_paged tui_show_dry_run "$appid" || true
				;;
			"[View] Paths (cache / install)")
				tui_run_paged show_paths "$appid" "$(tui_json_flag)" || true
				;;
			"[View] Launch stats")
				tui_run_paged launch_stats "$appid" "$(tui_json_flag)" || true
				;;
			"[View] Runtime status")
				tui_run_paged show_status "$appid" "$(tui_json_flag)" || true
				;;
			"[Edit] Quick toggles")
				tui_quick_toggles "$appid"
				;;
			"[Edit] Advanced config")
				tui_advanced_config "$appid"
				;;
			"[Edit] Suggest from ProtonDB")
				tui_suggest_config_menu "$appid"
				;;
			"[Edit] Clear override")
				tui_clear_override_menu "$appid"
				;;
			"[Edit] Open in \$EDITOR")
				tui_edit_appid_config "$appid"
				;;
			"[Edit] Set preset (re-init)")
				tui_init_game_config "$appid"
				;;
			"[Manage] Validate config")
				tui_run_paged validate_config "$appid" "$(tui_json_flag)" || true
				;;
			"[Manage] Delete per-game config")
				tui_delete_game_config "$appid"
				;;
			"[Hub] Community configs")
				tui_hub_game_actions "$appid"
				;;
			"Back to games menu"|*)
				tui_crumb_leave
				return 0
				;;
		esac
	done
}

# tui_games_menu — Per-game browsing and library maintenance.
tui_games_menu() {
	local action appid
	tui_crumb_enter "Games"
	tui_remember_main_menu "Games"
	tui_games_cache_start

	while true; do
		TUI_MENU_CONTEXT=games
		if tui_has_fzf; then
			action="$(tui_fzf_games_hub_pick "$(tui_crumb_label "(filter: ${TUI_GAME_FILTER:-all})")")" || {
				tui_crumb_leave
				return 0
			}
		else
			action="$(tui_games_hub_menu_select_fallback)" || {
				tui_crumb_leave
				return 0
			}
		fi

		case "$action" in
			"Browse & configure game")
				appid="$(tui_pick_game_appid)" || continue
				tui_game_actions "$appid"
				;;
			"Recent games")
				tui_recent_games_menu
				;;
			"Bulk change INCLUDE preset")
				tui_bulk_preset_menu
				;;
			"Init unconfigured games")
				tui_init_unconfigured_menu
				;;
			"Prune uninstalled configs")
				tui_prune_uninstalled_menu
				;;
			*)
				tui_crumb_leave
				return 0
				;;
		esac
	done
}
