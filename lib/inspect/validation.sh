# shellcheck shell=bash
# lib/inspect/validation.sh

# _validate_file_wrapper_flag_overlaps — Same-file LAUNCH_WRAPPERS* vs built-in feature flags.
_validate_file_wrapper_flag_overlaps() {
	local file=$1
	local line_num=0 line key value
	local file_gamemode=0 file_gamescope=0 file_mangohud=0 file_game_perf=1 file_dlss_swapper=0
	local file_disable_steam_deck=0
	local wrappers_before="" wrappers="" msg issues=0
	local -a msgs=()

	[[ -f "$file" ]] || return 0

	while IFS= read -r line || [[ -n "$line" ]]; do
		((line_num++)) || true
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] || [[ "$line" =~ ^INCLUDE= ]] && continue
		[[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
		key="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2]}"
		value="${value#\"}"; value="${value%\"}"
		case "$key" in
			GAMEMODE) [[ "$value" == "1" ]] && file_gamemode=1 ;;
			GAMESCOPE) [[ "$value" == "1" ]] && file_gamescope=1 ;;
			MANGOHUD) [[ "$value" == "1" ]] && file_mangohud=1 ;;
			GAME_PERFORMANCE) [[ "$value" == "0" ]] && file_game_perf=0 ;;
			DISABLE_STEAM_DECK) [[ "$value" == "1" ]] && file_disable_steam_deck=1 ;;
			DLSS_SWAPPER)
				case "$value" in
					1|yes|true|on|dll|DLL|YES|TRUE|ON) file_dlss_swapper="$value" ;;
				esac
				;;
			LAUNCH_WRAPPERS_BEFORE) wrappers_before="$value" ;;
			LAUNCH_WRAPPERS) wrappers="$value" ;;
		esac
	done < "$file"

	while IFS= read -r msg; do
		[[ -n "$msg" ]] || continue
		msgs+=("$msg")
	done < <(
		GAMEMODE=$file_gamemode GAMESCOPE=$file_gamescope MANGOHUD=$file_mangohud \
			GAME_PERFORMANCE=$file_game_perf DLSS_SWAPPER=$file_dlss_swapper \
			DISABLE_STEAM_DECK=$file_disable_steam_deck \
			LAUNCH_WRAPPERS_BEFORE="$wrappers_before" LAUNCH_WRAPPERS="$wrappers" \
			launch_wrapper_config_conflict_errors
	)

	for msg in "${msgs[@]}"; do
		echo "$file: $msg"
		((issues++)) || true
	done

	return "$issues"
}

# _validate_resolved_launch_wrappers_for_appid — Layered config + simulated launch chain checks.
_validate_resolved_launch_wrappers_for_appid() {
	local appid=$1 file=$2
	local line issues=0 saved_is_native

	[[ "$appid" =~ ^[0-9]+$ ]] || return 0

	reset_config_state
	steam_app_id="$appid"
	load_launch_config
	apply_defaults
	parse_game_extra_args

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		echo "$file: resolved: $line"
		((issues++)) || true
	done < <(launch_wrapper_config_conflict_errors)

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		echo "$file: resolved: $line"
		((issues++)) || true
	done < <(inject_provider_conflict_errors)

	saved_is_native=$is_native
	optional_tool_installed() { return 0; }
	command_available() { return 0; }
	default_online_cpus() { echo 0-3; }
	is_native=$saved_is_native
	launch=()
	apply_proton_env
	build_launch_chain

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		echo "$file: resolved: $line"
		((issues++)) || true
	done < <(launch_chain_duplicate_wrapper_errors)

	return "$issues"
}

# validate_single_config_file — Lint one .env file; print issues to stdout.
validate_single_config_file() {
	local file=$1
	local line_num=0 line key value preset_path issues=0

	[[ -f "$file" ]] || return 0

	while IFS= read -r line || [[ -n "$line" ]]; do
		((line_num++)) || true
		local raw="$line"
		line="${line%%#*}"
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"
		[[ -z "$line" ]] && continue

		if [[ "$line" =~ ^INCLUDE=(.+)$ ]]; then
			preset_path="${BASH_REMATCH[1]}"
			preset_path="${preset_path#"${preset_path%%[![:space:]]*}"}"
			preset_path="${preset_path%"${preset_path##*[![:space:]]}"}"
			preset_path="${preset_path#\"}"; preset_path="${preset_path%\"}"
			if declare -f is_safe_include_path >/dev/null 2>&1 && ! is_safe_include_path "$preset_path"; then
				echo "$file:$line_num: unsafe INCLUDE path: $preset_path"
				((issues++)) || true
				continue
			fi
			if [[ ! -f "$LAUNCHD_DIR/$preset_path" ]]; then
				echo "$file:$line_num: INCLUDE target missing: $preset_path"
				((issues++)) || true
			fi
			continue
		fi

		[[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || {
			echo "$file:$line_num: invalid line: $raw"
			((issues++)) || true
			continue
		}
		key="${BASH_REMATCH[1]}"
		value="${BASH_REMATCH[2]}"
		if ! known_config_key "$key"; then
			echo "$file:$line_num: unknown key: $key"
			((issues++)) || true
		fi
		if [[ "$(config_key_kind "$key")" == enum ]]; then
			value="${value#\"}"; value="${value%\"}"
			if [[ -n "$value" ]] && ! config_key_enum_value_known "$key" "$value"; then
				echo "$file:$line_num: $key must be one of: $(config_key_enum_values "$key") (got: $value)"
				((issues++)) || true
			fi
		fi
		case "$key" in
			LAUNCH_WRAPPERS|LAUNCH_WRAPPERS_BEFORE)
				local wrapper
				for wrapper in $value; do
					launch_wrapper_available "$wrapper" || {
						local hint=""
						hint="$(tool_install_hint "$wrapper" 2>/dev/null || true)"
						echo "$file:$line_num: wrapper not found: $wrapper${hint:+ — $hint}"
						((issues++)) || true
					}
				done
				;;
			FRAME_RATE)
				value="${value#\"}"; value="${value%\"}"
				if [[ -n "$value" && "$value" != "0" ]] && ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
					echo "$file:$line_num: FRAME_RATE must be a positive integer (got: $value)"
					((issues++)) || true
				fi
				;;
			GAMESCOPE_W|GAMESCOPE_H|GAMESCOPE_R|GAMESCOPE_FRAME_LIMIT|GAMESCOPE_FOCUSED_FPS|GAMESCOPE_UNFOCUSED_FPS)
				value="${value#\"}"; value="${value%\"}"
				if [[ -n "$value" && ! "$value" =~ ^[1-9][0-9]*$ ]]; then
					echo "$file:$line_num: $key must be a positive integer (got: $value)"
					((issues++)) || true
				fi
				;;
			GAMESCOPE_FSR_SHARPNESS)
				value="${value#\"}"; value="${value%\"}"
				if [[ ! "$value" =~ ^[0-9]+$ || "$value" -gt 20 ]]; then
					echo "$file:$line_num: GAMESCOPE_FSR_SHARPNESS must be an integer from 0 to 20 (got: $value)"
					((issues++)) || true
				fi
				;;
			SPECIAL_K_DLL|RESHADE_DLL)
				value="${value#\"}"; value="${value%\"}"
				if ! inject_proxy_name_is_safe "$value"; then
					echo "$file:$line_num: $key must be a proxy DLL leaf name (got: $value)"
					((issues++)) || true
				fi
				;;
			GAMESCOPE_RESHADE_TECHNIQUE)
				value="${value#\"}"; value="${value%\"}"
				if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
					echo "$file:$line_num: GAMESCOPE_RESHADE_TECHNIQUE must be a non-negative integer (got: $value)"
					((issues++)) || true
				fi
				;;
			GAMESCOPE)
				[[ "$value" == "1" ]] && [[ "${FORCE_PROTON:-0}" != "1" ]] && {
					local appid_from_file
					appid_from_file="$(basename "$file" .env)"
					if [[ "$appid_from_file" =~ ^[0-9]+$ ]] && detect_native_game "$appid_from_file" 0; then
						echo "$file:$line_num: GAMESCOPE=1 on native game without FORCE_PROTON=1"
						((issues++)) || true
					fi
				}
				;;
			FORCE_NATIVE|FORCE_PROTON) ;;
	esac
	done < "$file"

	if grep -qE '^[[:space:]]*FORCE_NATIVE=1' "$file" 2>/dev/null \
		&& grep -qE '^[[:space:]]*FORCE_PROTON=1' "$file" 2>/dev/null; then
		echo "$file: conflicting FORCE_NATIVE=1 and FORCE_PROTON=1"
		((issues++)) || true
	fi

	_validate_file_wrapper_flag_overlaps "$file" || issues=$((issues + $?))

	return "$issues"
}

# scan_anticheat — Compare filesystem anticheat markers against anticheat-appids.txt.
scan_anticheat() {
	local update_list=${1:-0}
	local fs list ac_type added=0

	echo "=== Anticheat scan ==="
	printf '%-10s %-4s %-4s %-8s %s\n' APPID FS LIST TYPE NAME

	_scan_anticheat_one() {
		local appid=$1 name=$2 _manifest=$3
		fs=no; list=no
		ac_type="$(detect_anticheat_type "$appid")"
		case "$ac_type" in
			eac|battleye) fs=yes ;;
		esac
		detect_anticheat_in_list "$appid" && list=yes
		[[ -z "$ac_type" ]] && ac_type="-"

		[[ "$fs" == yes || "$list" == yes ]] || return 0
		printf '%-10s %-4s %-4s %-8s %s\n' "$appid" "$fs" "$list" "$ac_type" "$name"

		if [[ "$fs" == yes && "$list" == no ]]; then
			echo "  → missing from anticheat-appids.txt: $appid ($name)"
			if [[ "$update_list" == "1" ]] && ! grep -qx "$appid" "$LAUNCHD_DIR/anticheat-appids.txt" 2>/dev/null; then
				echo "$appid" >> "$LAUNCHD_DIR/anticheat-appids.txt"
				echo "    added $appid to anticheat-appids.txt"
				((added++)) || true
			fi
		fi
		if [[ "$fs" == no && "$list" == yes ]]; then
			echo "  → list-only (no install-dir markers): $appid ($name)"
		fi
	}

	foreach_installed_game _scan_anticheat_one

	if (( added > 0 )); then
		echo "Added $added AppID(s) to anticheat-appids.txt"
	fi
	return 0
}

# scan_detections — Report heuristic vs list mismatches and tuning hints.
scan_detections() {
	echo "=== Detection audit ==="

	_scan_detections_one() {
		local appid=$1 name=$2 _manifest=$3
		local native_heur native_list ac_fs ac_list

		native_heur=no; native_list=no; ac_fs=no; ac_list=no
		detect_native_game "$appid" 1 && native_heur=yes
		appid_in_list_file "$appid" "$LAUNCHD_DIR/native-appids.txt" && native_list=yes
		detect_anticheat_filesystem "$appid" && ac_fs=yes
		detect_anticheat_in_list "$appid" && ac_list=yes

		if [[ "$native_heur" == yes && "$native_list" == no ]]; then
			echo "native heuristic only: $appid ($name) — consider native-appids.txt"
		fi
		if [[ "$native_heur" == no && "$native_list" == yes ]]; then
			echo "native list only: $appid ($name) — verify FORCE_NATIVE or list entry"
		fi
		if [[ "$ac_fs" == yes && "$ac_list" == no ]]; then
			echo "anticheat fs only: $appid ($name) — run --scan-anticheat --update-list"
		fi
		if detect_dlss_present "$appid"; then
			local dlss_cfg
			dlss_cfg="$(resolve_appid_env_path "$appid")"
			if [[ -f "$dlss_cfg" ]] && grep -Eq \
				'^[[:space:]]*(DLSS_SWAPPER=(1|dll|yes|true|on)|PROTON_DLSS_UPGRADE=1)|(^|[[:space:]=])dlss-swapper(-dll)?([[:space:]]|$)' \
				"$dlss_cfg" 2>/dev/null; then
				return 0
			fi
			echo "dlss present: $appid ($name) — consider DLSS_SWAPPER=1 or PROTON_DLSS_UPGRADE=1"
		fi
	}

	foreach_installed_game _scan_detections_one
}

# validate_config — Lint one AppID config, all per-game configs, or default + presets.
validate_config() {
	local target=${1:-all} json=${2:-0} issues=0 file
	local -a issue_lines=()
	local line validation_profiles

	# A validation batch resolves many configs against the same machine and
	# launch.d tree. Detect profiles and canonicalize shared INCLUDEs once.
	validation_profiles="$(detect_default_profiles 2>/dev/null || true)"
	local LAUNCHLAYER_PROFILES="$validation_profiles"
	local LAUNCHLAYER_CACHE_INCLUDE_RESOLUTION=1
	CONFIG_RESOLVED_INCLUDE_BY_KEY=()

	_run_validation() {
		local t=${1:-all}
		case "$t" in
			all)
				local -A validated_appids=() v_appid
				validate_single_config_file "$LAUNCHD_DIR/default.env" || issues=$((issues + $?))
				for file in "$LAUNCHD_DIR"/presets/*.env; do
					[[ -f "$file" ]] || continue
					validate_single_config_file "$file" || issues=$((issues + $?))
				done
				for file in "$GAMES_DIR"/[0-9]*.env; do
					[[ -f "$file" ]] || continue
					v_appid="${file##*/}"
					v_appid="${v_appid%.env}"
					[[ -n "${validated_appids[$v_appid]+x}" ]] && continue
					validated_appids["$v_appid"]=1
					validate_single_config_file "$file" || issues=$((issues + $?))
					_validate_resolved_launch_wrappers_for_appid "$v_appid" "$file" \
						|| issues=$((issues + $?))
				done
				;;
			default|presets|local)
				if [[ "$t" == default ]]; then
					validate_single_config_file "$LAUNCHD_DIR/default.env" || issues=$((issues + $?))
				elif [[ "$t" == local ]]; then
					[[ -f "$LAUNCHD_DIR/local.env" ]] \
						&& validate_single_config_file "$LAUNCHD_DIR/local.env" || issues=$((issues + $?)) \
						|| echo "No config: $LAUNCHD_DIR/local.env" >&2
				else
					for file in "$LAUNCHD_DIR"/presets/*.env; do
						[[ -f "$file" ]] || continue
						validate_single_config_file "$file" || issues=$((issues + $?))
					done
				fi
				;;
			*)
				if [[ "$t" != all && "$t" != default && "$t" != presets && ! "$t" =~ ^[0-9]+$ ]]; then
					t="$(resolve_appid_query "$t")" || return $?
				fi
				[[ "$t" =~ ^[0-9]+$ ]] || {
					echo "Usage: $0 --validate-config [APPID|NAME|all|default|presets] [--json]" >&2
					return 1
				}
				file="$(resolve_appid_env_path "$t")"
				if ! appid_env_exists "$t"; then
					echo "No config: $file" >&2
					return 1
				fi
				validate_single_config_file "$file" || issues=$((issues + $?))
				_validate_resolved_launch_wrappers_for_appid "$t" "$file" \
					|| issues=$((issues + $?))
				;;
		esac
	}

		if [[ "$json" == "1" ]]; then
		issues=0
		while IFS= read -r line; do
			[[ -n "$line" ]] && issue_lines+=("$line")
		done < <(_run_validation "$target")
		printf '{"target":%s,"issue_count":%s,"issues":' \
			"$(json_string "$target")" "$issues"
		json_array_strings issue_lines
		printf '}\n'
		(( issues == 0 )) || return "$issues"
		return 0
	fi

	_run_validation "$target"

	if (( issues == 0 )); then
		echo "Validation passed (0 issues)"
	else
		echo "Validation failed ($issues issue(s))"
	fi
	return "$issues"
}
