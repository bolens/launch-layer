# shellcheck shell=bash
# lib/commands/games.sh
# show_cpu_topology — Print lscpu summary and detected X3D_CPUS range.
show_cpu_topology() {
	echo "=== CPU topology ==="
	if command_available lscpu; then
		lscpu | grep -E 'Model name|CPU\(s\)|Thread|Core|Socket|NUMA|On-line|MHz' || true
	else
		echo "lscpu is not installed$(tool_warn_suffix lscpu)"
		echo "Online CPUs: $(nproc_portable)"
	fi
	echo
	echo "Detected X3D_CPUS: $(detect_x3d_cpus | tr ',' '-')"
	echo "Default route NIC: $(detect_default_nic 2>/dev/null || echo unknown)"
	echo "Cached in: $X3D_CPUS_CACHE_FILE"
}

# list_games — Tabular or JSON list with launch-time detection (heuristics + lists).
list_games() {
	local configured_only=${1:-0} json=${2:-0} grep_pattern=${3:-}
	local cfg native eac ac_type engine row
	local -a _list_games_rows=() _list_games_cache_rows=()

	CLI_JSON_OUTPUT=$json

	_list_games_one() {
		local appid=$1 name=$2 _manifest=$3

		cli_scan_progress_tick

		cfg=no; native=no; eac=no
		appid_env_exists "$appid" && cfg=yes
		detect_native_game "$appid" 1 && native=yes
		ac_type="$(detect_anticheat_type "$appid")"
		engine="$(detect_engine_hint "$appid")"
		[[ -z "$ac_type" ]] && ac_type="-"
		[[ "$ac_type" != "-" ]] && eac=yes
		name="${name//$'\r'/ }"
		name="${name//$'\n'/ }"
		name="${name//$'\t'/ }"

		printf -v row '%-10s %-5s %-5s %-8s %-12s %s' \
			"$appid" "$cfg" "$native" "$ac_type" "$engine" "$name"
		_list_games_cache_rows+=("$row")

		game_name_matches_grep "$name" "$grep_pattern" || return 0
		[[ "$configured_only" == "1" && "$cfg" == no ]] && return 0

		if [[ "$json" == "1" ]]; then
			printf '{"appid":%s,"configured":%s,"native":%s,"eac":%s,"anticheat_type":%s,"engine":%s,"name":%s}\n' \
				"$(json_string "$appid")" \
				"$(json_bool "$([[ "$cfg" == yes ]] && echo 1 || echo 0)")" \
				"$(json_bool "$([[ "$native" == yes ]] && echo 1 || echo 0)")" \
				"$(json_bool "$([[ "$eac" == yes ]] && echo 1 || echo 0)")" \
				"$(json_string "$ac_type")" \
				"$(json_string "$engine")" \
				"$(json_string "$name")"
		else
			_list_games_rows+=("$row")
		fi
	}

	cli_scan_progress_begin "Listing installed games"
	foreach_installed_game _list_games_one
	cli_scan_progress_end
	if [[ "${LAUNCH_QUIET:-0}" != "1" && "${LIST_GAMES_UPDATE_CACHE:-1}" != "0" && ${#_list_games_cache_rows[@]} -gt 0 ]]; then
		if ! tui_games_cache_persist_lines "${_list_games_cache_rows[@]}" 2>/dev/null; then
			debug "TUI games cache update skipped: cache directory is not writable"
		fi
	fi

	if [[ "$json" != "1" ]]; then
		printf '%-10s %-5s %-5s %-8s %-12s %s\n' APPID CFG NAT AC-TYPE ENGINE NAME
		for row in "${_list_games_rows[@]}"; do
			printf '%s\n' "$row"
		done
	fi
}

# resolve_appid_arg — Resolve CLI AppID or name fragment; prints AppID.
resolve_appid_arg() {
	local query=$1
	[[ -n "$query" ]] || return 1
	resolve_appid_query "$query"
}

# init_appid_config — Create games/<AppID>.env from a named preset.
init_appid_config() {
	local appid=$1 preset=${2:-} force=${3:-0} name path
	[[ "$appid" =~ ^[0-9]+$ ]] || {
		echo "Usage: $0 --init-appid APPID|NAME [preset] [--force]" >&2
		return 1
	}
	is_installed_game_appid "$appid" || {
		echo "AppID $appid is not an installed game." >&2
		return 1
	}
	name="$(get_game_name "$appid" 2>/dev/null || true)"
	[[ -n "$name" ]] || {
		echo "AppID $appid not found in installed Steam libraries." >&2
		return 1
	}
	path="$(appid_env_write_path "$appid")"
	if appid_env_exists "$appid" && [[ "$force" != "1" ]]; then
		echo "Config already exists: $(resolve_appid_env_path "$appid") (use --force to overwrite)" >&2
		return 1
	fi
	if [[ -z "$preset" ]]; then
		preset="$(suggest_preset_for_appid "$appid")"
	fi
	case "$preset" in
		standard|competitive|lightweight|native) ;;
		*) echo "Unknown preset: $preset" >&2; return 1 ;;
	esac
	write_appid_env_scaffold "$appid" "$name" "$preset" "$path"
	if [[ "$force" == "1" ]]; then
		echo "Overwrote $path (preset: $preset)"
	else
		echo "Created $path (preset: $preset)"
	fi
}

# set_include_preset — Point per-game INCLUDE= at a named preset.
set_include_preset() {
	local appid=$1 preset=$2 file
	[[ "$appid" =~ ^[0-9]+$ ]] || return 1
	case "$preset" in
		standard|competitive|lightweight|native) ;;
		*) echo "Unknown preset: $preset" >&2; return 1 ;;
	esac
	appid_env_exists "$appid" || init_appid_config "$appid" "" 0 || return 1
	file="$(appid_env_write_path "$appid")"
	appid_env_upsert "$file" "INCLUDE" "presets/${preset}.env"
	echo "Set INCLUDE=presets/${preset}.env in $(basename "$file")"
}

# bulk_set_include_preset — Apply INCLUDE preset to many installed games.
bulk_set_include_preset() {
	local preset="" dry_run=0 json=0 all_configured=0 all_installed=0 grep_pattern=""
	local -a appids=() resolved=() arg
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--dry-run) dry_run=1; shift ;;
			--json) json=1; shift ;;
			--all-configured) all_configured=1; shift ;;
			--all-installed) all_installed=1; shift ;;
			--grep) grep_pattern=${2:-}; shift 2 ;;
			standard|competitive|lightweight|native)
				[[ -z "$preset" ]] && preset=$1
				shift
				;;
			*)
				resolved+=("$1")
				shift
				;;
		esac
	done
	[[ -n "$preset" ]] || {
		echo "Usage: $0 --bulk-set-include PRESET [--all-configured|--all-installed] [--grep NAME] [APPID|NAME...] [--dry-run] [--json]" >&2
		return 1
	}
	for arg in "${resolved[@]}"; do
		if [[ "$arg" =~ ^[0-9]+$ ]]; then
			appids+=("$arg")
		else
			appids+=("$(resolve_appid_arg "$arg")") || return 1
		fi
	done
	if ((${#appids[@]} == 0)); then
		_bulk_collect_include_appids() {
			local appid=$1 name=$2 _manifest=$3
			game_name_matches_grep "$name" "$grep_pattern" || return 0
			if [[ "$all_configured" == "1" ]] && ! appid_env_exists "$appid"; then
				return 0
			fi
			appids+=("$appid")
		}
		cli_scan_progress_begin "Collecting games for bulk INCLUDE update"
		foreach_installed_game _bulk_collect_include_appids || true
		cli_scan_progress_end
		[[ "$all_installed" != "1" && "$all_configured" != "1" && -z "$grep_pattern" ]] && {
			echo "Specify --all-configured, --all-installed, --grep NAME, or one or more APPID|NAME targets." >&2
			return 1
		}
	fi
	((${#appids[@]})) || {
		echo "No games matched the requested scope."
		return 0
	}
	if [[ "$dry_run" == "1" ]]; then
		if [[ "$json" == "1" ]]; then
			printf '{"preset":%s,"count":%s,"appids":%s}\n' \
				"$(json_string "$preset")" \
				"${#appids[@]}" \
				"$(json_array_strings appids)"
		else
			echo "Would set INCLUDE=presets/${preset}.env on ${#appids[@]} game(s):"
			printf '  %s\n' "${appids[@]}"
		fi
		return 0
	fi
	local -i updated=0
	for appid in "${appids[@]}"; do
		set_include_preset "$appid" "$preset" && ((updated++)) || true
	done
	if [[ "$json" == "1" ]]; then
		printf '{"preset":%s,"updated":%s}\n' \
			"$(json_string "$preset")" "$updated"
	else
		echo "Updated INCLUDE preset on $updated game(s)."
	fi
}

# suggest_config — Rank ProtonDB reports for this machine; optionally apply allowlisted knobs.
# apply: 0 = preview only, 1 = write allowlisted keys into games/<AppID>.env
suggest_config() {
	local appid=$1 apply=${2:-0}
	local env_json

	command_required_or_fail python3 "ProtonDB suggest" || return 1
	[[ -n "$appid" ]] || {
		echo "suggest_config: AppID required" >&2
		return 1
	}
	if [[ "$appid" =~ ^[0-9]+$ ]]; then
		if declare -f find_app_manifest >/dev/null 2>&1 \
			&& find_app_manifest "$appid" >/dev/null 2>&1 \
			&& ! is_installed_game_appid "$appid"; then
			echo "AppID $appid is an installed Steam tool, not a game." >&2
			return 1
		fi
	else
		appid="$(resolve_appid_arg "$appid")" || return $?
	fi

	load_profile_config
	load_config_file "$LAUNCHD_DIR/default.env" 0
	[[ -f "$LAUNCHD_DIR/local.env" ]] && load_config_file "$LAUNCHD_DIR/local.env" 0
	apply_defaults

	env_json="$(show_detect_environment --json)"
	python3 "$SCRIPT_DIR/scripts/protondb_suggest.py" "$appid" "$env_json" "$apply" "$GAMES_DIR"
}
