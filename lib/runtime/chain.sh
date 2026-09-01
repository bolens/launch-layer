# shellcheck shell=bash
# lib/runtime/chain.sh — Wrapper chain assembly for Steam launch.

[[ -n "${LAUNCHLAYER_RUNTIME_CHAIN_LOADED:-}" ]] && return 0
LAUNCHLAYER_RUNTIME_CHAIN_LOADED=1

# append_launch_wrappers_from — Append installed binaries from a wrapper list to launch[].
append_launch_wrappers_from() {
	local wrappers=$1 wrapper
	for wrapper in $wrappers; do
		if launch_wrapper_available "$wrapper"; then
			launch+=("$wrapper")
		else
			debug "launch wrapper skipped (not installed): $wrapper"
		fi
	done
}

# append_launch_wrappers — Prepend LAUNCH_WRAPPERS_BEFORE binaries to the chain.
append_launch_wrappers() {
	append_launch_wrappers_from "${LAUNCH_WRAPPERS_BEFORE}"
}

# append_launch_wrappers_after_performance — Append LAUNCH_WRAPPERS after game-performance.
append_launch_wrappers_after_performance() {
	append_launch_wrappers_from "${LAUNCH_WRAPPERS}"
}

# parse_game_extra_args — Split GAME_EXTRA_ARGS into game_extra_argv[].
parse_game_extra_args() {
	game_extra_argv=()
	[[ -n "${GAME_EXTRA_ARGS:-}" ]] || return 0
	local arg
	read -r -a game_extra_argv <<< "$GAME_EXTRA_ARGS"
	for arg in "${game_extra_argv[@]}"; do
		debug "extra arg: $arg"
	done
}

# append_gamescope_extra_argv — Split GAMESCOPE_EXTRA_ARGS into launch[].
append_gamescope_extra_argv() {
	local arg
	[[ -n "${GAMESCOPE_EXTRA_ARGS:-}" ]] || return 0
	# shellcheck disable=SC2086
	read -r -a _gs_extra <<< "$GAMESCOPE_EXTRA_ARGS"
	for arg in "${_gs_extra[@]}"; do
		launch+=("$arg")
	done
}

# build_launch_chain — Assemble the wrapper prefix executed before Steam's %command%.
#
# Typical chain:
#   [unshare -n?] → [conty?] → [wrappers_before] → gamemoderun → taskset → game-performance
#   → [dlss-swapper] → [wrappers] → [env -u LD_PRELOAD] gamescope … -- [env LD_PRELOAD=]
#   → [obs/replay/discord] → [mangohud]
build_launch_chain() {
	local use_mangoapp=0
	local dlss_bin="" conty_bin="" obs_bin="" replay_bin="" discord_bin=""
	local skip_gamescope=0
	local nested_preload=""
	local use_nested_fix=0

	launch=( )

	if [[ "${BLOCK_INTERNET:-0}" == "1" && "${LAUNCHLAYER_BLOCK_INTERNET_WRAP:-}" == unshare ]]; then
		if command_available unshare; then
			launch+=(unshare -n -r)
		fi
	fi

	if conty_bin="$(resolve_conty_bin 2>/dev/null)"; then
		launch+=("$conty_bin")
	elif [[ "${CONTY:-0}" == "1" ]]; then
		debug "CONTY=1 but conty binary unavailable"
	fi

	append_launch_wrappers

	if [[ "${GAMEMODE:-1}" == "1" ]] && optional_tool_installed gamemoderun; then
		launch+=(gamemoderun)
	elif [[ "${GAMEMODE:-1}" == "1" ]]; then
		debug "gamemoderun unavailable — continuing without GameMode wrapper"
	fi

	if [[ "${DISABLE_CPU_AFFINITY:-0}" != "1" ]] && optional_tool_installed taskset; then
		launch+=(taskset -c "${CPU_AFFINITY_RANGE:-${X3D_CPUS:-$(default_online_cpus)}}")
	elif [[ "${DISABLE_CPU_AFFINITY:-0}" != "1" ]]; then
		debug "taskset unavailable — continuing without CPU affinity wrapper"
	fi
	if [[ "${GAME_PERFORMANCE:-1}" == "1" ]] && launch_wrapper_available game-performance; then
		launch+=(game-performance)
	fi
	if dlss_bin="$(resolve_dlss_swapper_bin)"; then
		if launch_wrapper_available "$dlss_bin"; then
			launch+=("$dlss_bin")
		else
			debug "$dlss_bin unavailable — continuing without DLSS swapper wrapper"
		fi
	fi
	append_launch_wrappers_after_performance

	if [[ "${GAMESCOPE:-0}" == "1" && "$is_native" == "1" && "${FORCE_PROTON:-0}" != "1" ]]; then
		warn "GAMESCOPE=1 on native game — set FORCE_PROTON=1 if intentional"
	fi

	# Skip nested Gamescope inside gamescope-session / Deck gamemode.
	if [[ "${GAMESCOPE:-0}" == "1" ]] && gamescope_session_active 2>/dev/null; then
		skip_gamescope=1
		warn "GAMESCOPE=1 skipped — already inside gamescope-session (ScopeBuddy-style nest skip)"
	fi

	if [[ "${GAMESCOPE:-0}" == "1" && "$skip_gamescope" != "1" ]] && optional_tool_installed gamescope; then
		# Nested desktop fix: strip Steam/overlay LD_PRELOAD from gamescope, re-apply after --.
		if [[ "${GAMESCOPE_NESTED_FIX:-1}" == "1" ]]; then
			nested_preload="${LD_PRELOAD:-}"
			use_nested_fix=1
			launch+=(env -u LD_PRELOAD)
		fi
		launch+=(gamescope)
		[[ -n "${GAMESCOPE_W:-}" ]] && launch+=(-W "${GAMESCOPE_W}")
		[[ -n "${GAMESCOPE_H:-}" ]] && launch+=(-H "${GAMESCOPE_H}")
		[[ -n "${GAMESCOPE_R:-}" ]] && launch+=(-r "${GAMESCOPE_R}")
		launch+=(-f --force-grab-cursor)
		[[ "${GAMESCOPE_ADAPTIVE_SYNC:-0}" == "1" ]] && launch+=(--adaptive-sync)
		[[ "${GAMESCOPE_EXPOSE_WAYLAND:-0}" == "1" ]] && launch+=(--expose-wayland)
		[[ "${GAMESCOPE_FSR:-0}" == "1" ]] && launch+=(--fsr-sharpness "${GAMESCOPE_FSR_SHARPNESS:-5}")
		[[ "${GAMESCOPE_HDR:-0}" == "1" ]] && launch+=(--hdr-enabled)
		if [[ -n "${GAMESCOPE_PREFER_OUTPUT:-}" ]]; then
			launch+=(-O "${GAMESCOPE_PREFER_OUTPUT}")
		fi
		if [[ -n "${GAMESCOPE_FRAME_LIMIT:-}" ]]; then
			launch+=(--framerate-limit "${GAMESCOPE_FRAME_LIMIT}")
		fi
		if [[ -n "${GAMESCOPE_FILTER:-}" ]]; then
			launch+=(--filter "${GAMESCOPE_FILTER}")
		fi
		if [[ -n "${GAMESCOPE_RESHADE_EFFECT:-}" ]]; then
			launch+=(--reshade-effect "${GAMESCOPE_RESHADE_EFFECT}")
		fi
		if [[ -n "${GAMESCOPE_RESHADE_TECHNIQUE:-}" ]]; then
			launch+=(--reshade-technique-idx "${GAMESCOPE_RESHADE_TECHNIQUE}")
		fi
		if [[ -n "${GAMESCOPE_FOCUSED_FPS:-}" ]]; then
			# Newer gamescope: --fps-limit; keep as focused when only one set.
			launch+=(--fps-limit "${GAMESCOPE_FOCUSED_FPS}")
		fi
		if [[ -n "${GAMESCOPE_UNFOCUSED_FPS:-}" ]]; then
			launch+=(--unfocused-fps-limit "${GAMESCOPE_UNFOCUSED_FPS}")
		fi
		append_gamescope_extra_argv
		# --mangoapp integrates MangoHUD inside gamescope (avoids double-wrapping).
		if [[ "${BENCHMARK:-0}" != "1" && "${MANGOHUD:-0}" == "1" ]]; then
			launch+=(--mangoapp)
			use_mangoapp=1
		fi
		launch+=(--)
		if [[ "$use_nested_fix" == "1" && -n "$nested_preload" ]]; then
			launch+=(env "LD_PRELOAD=${nested_preload}")
		fi
	elif [[ "${GAMESCOPE:-0}" == "1" && "$skip_gamescope" != "1" ]]; then
		debug "gamescope unavailable — continuing without Gamescope wrapper"
	fi

	if obs_bin="$(resolve_obs_vkcapture_bin 2>/dev/null)"; then
		launch+=("$obs_bin")
	elif [[ "${OBS_VKCAPTURE:-0}" == "1" ]]; then
		debug "OBS_VKCAPTURE=1 but obs-gamecapture/obs-vkcapture missing"
	fi

	if replay_bin="$(resolve_replay_bin 2>/dev/null)"; then
		# gpu-screen-recorder is often a companion, not a %command% wrapper — only wrap PATH tools that take a command.
		case "$replay_bin" in
			replay-sorcery) launch+=("$replay_bin") ;;
			*)
				debug "REPLAY_CAPTURE tool=$replay_bin — start externally or via PRE_LAUNCH_CMD (not chain-wrapped)"
				;;
		esac
	elif [[ "${REPLAY_CAPTURE:-0}" == "1" ]]; then
		debug "REPLAY_CAPTURE=1 but no replay tool found"
	fi

	if discord_bin="$(resolve_discord_ipc_bin 2>/dev/null)"; then
		launch+=("$discord_bin")
	fi

	if [[ "${BENCHMARK:-0}" != "1" && "${MANGOHUD:-0}" == "1" && "$use_mangoapp" != "1" ]] \
		&& optional_tool_installed mangohud; then
		launch+=(mangohud)
	elif [[ "${BENCHMARK:-0}" != "1" && "${MANGOHUD:-0}" == "1" && "$use_mangoapp" != "1" ]]; then
		debug "mangohud unavailable — continuing without MangoHUD wrapper"
	fi

	# --mangoapp already integrates MangoHUD; exporting MANGOHUD=1 would inject a
	# second overlay via the Vulkan/OpenGL layer path.
	if [[ "$use_mangoapp" == "1" ]]; then
		unset MANGOHUD
		debug "MANGOHUD unset — gamescope --mangoapp handles the overlay"
	fi

	debug "launch chain: ${launch[*]}"
}

# launch_wrapper_config_conflict_errors — Flag LAUNCH_WRAPPERS* overlapping built-in features.
launch_wrapper_config_conflict_errors() {
	local wrapper
	local -a errors=()
	local dlss_enabled=0

	resolve_dlss_swapper_bin >/dev/null && dlss_enabled=1

	for wrapper in ${LAUNCH_WRAPPERS_BEFORE:-} ${LAUNCH_WRAPPERS:-}; do
		case "$wrapper" in
			gamemoderun)
				[[ "${GAMEMODE:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes gamemoderun while GAMEMODE=1")
				;;
			gamescope|scopebuddy|scb)
				[[ "${GAMESCOPE:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes $wrapper while GAMESCOPE=1")
				;;
			mangohud)
				[[ "${MANGOHUD:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes mangohud while MANGOHUD=1")
				;;
			game-performance)
				[[ "${GAME_PERFORMANCE:-1}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes game-performance while GAME_PERFORMANCE=1")
				;;
			dlss-swapper|dlss-swapper-dll)
				(( dlss_enabled )) \
					&& errors+=("LAUNCH_WRAPPERS includes $wrapper while DLSS_SWAPPER=${DLSS_SWAPPER}")
				;;
			sd0)
				[[ "${DISABLE_STEAM_DECK:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes sd0 while DISABLE_STEAM_DECK=1 (use one path)")
				;;
			obs-gamecapture|obs-vkcapture)
				[[ "${OBS_VKCAPTURE:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes $wrapper while OBS_VKCAPTURE=1")
				;;
			conty)
				[[ "${CONTY:-0}" == "1" ]] \
					&& errors+=("LAUNCH_WRAPPERS includes conty while CONTY=1")
				;;
		esac
	done

	if ((${#errors[@]})); then
		printf '%s\n' "${errors[@]}"
	fi
}

# warn_launch_chain_issues — Warn on config/chain wrapper conflicts; return 1 when any exist.
warn_launch_chain_issues() {
	local line had_issue=0

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		warn "launch chain: $line"
		had_issue=1
	done < <(launch_wrapper_config_conflict_errors)

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		warn "launch chain: $line"
		had_issue=1
	done < <(inject_provider_conflict_errors)

	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		warn "launch chain: $line"
		had_issue=1
	done < <(launch_chain_duplicate_wrapper_errors)

	(( !had_issue ))
}

# launch_chain_uses_mangohud — True when the resolved chain enables MangoHUD.
launch_chain_uses_mangohud() {
	local item
	for item in "${launch[@]}"; do
		[[ "$item" == mangohud || "$item" == --mangoapp ]] && return 0
	done
	return 1
}

# launch_chain_count_token — Count exact token matches in launch[].
launch_chain_count_token() {
	local token=$1 item count=0
	for item in "${launch[@]}"; do
		[[ "$item" == "$token" ]] && ((count++))
	done
	printf '%s' "$count"
}

# launch_chain_duplicate_wrapper_errors — One line per duplicate/conflict; empty when ok.
launch_chain_duplicate_wrapper_errors() {
	local wrapper item count=0
	local -a errors=()
	local has_mangohud=0 has_mangoapp=0

	for wrapper in gamemoderun game-performance dlss-swapper dlss-swapper-dll gamescope mangohud \
		obs-gamecapture obs-vkcapture conty; do
		count="$(launch_chain_count_token "$wrapper")"
		if (( count > 1 )); then
			errors+=("duplicate $wrapper in launch chain (count=$count)")
		fi
	done
	if (( $(launch_chain_count_token dlss-swapper) > 0 && $(launch_chain_count_token dlss-swapper-dll) > 0 )); then
		errors+=("dlss-swapper and dlss-swapper-dll both present in launch chain")
	fi

	for item in "${launch[@]}"; do
		[[ "$item" == mangohud ]] && has_mangohud=1
		[[ "$item" == --mangoapp ]] && has_mangoapp=1
	done
	if (( has_mangohud && has_mangoapp )); then
		errors+=("mangohud wrapper and gamescope --mangoapp both present")
	fi

	if ((${#errors[@]})); then
		printf '%s\n' "${errors[@]}"
	fi
}

# launch_chain_has_duplicate_wrappers — True when launch_chain_duplicate_wrapper_errors is non-empty.
launch_chain_has_duplicate_wrappers() {
	[[ -n "$(launch_chain_duplicate_wrapper_errors)" ]]
}
