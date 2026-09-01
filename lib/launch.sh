# shellcheck shell=bash
# shellcheck source=common.sh
# shellcheck source=config.sh
# shellcheck source=steam/detect.sh
# shellcheck source=hardware/cpu.sh
# shellcheck source=preflight.sh
# shellcheck source=runtime/chain.sh
# shellcheck source=vram.sh
# lib/launch.sh — Main game-launch orchestration pipeline.

[[ -n "${LAUNCHLAYER_LAUNCH_LOADED:-}" ]] && return 0
LAUNCHLAYER_LAUNCH_LOADED=1

# prepare_launch_context — Load config and build launch chain without running the game.
prepare_launch_context() {
	local appid=$1
	reset_config_state
	steam_app_id="$appid"
	load_launch_config
	apply_defaults
	apply_detected_defaults
	resolve_game_flags
	apply_auto_hardware_defaults
	parse_game_extra_args
	apply_launch_env_tuning
	apply_proton_env
	apply_hdr_tuning
	apply_malloc_allocator
	apply_launch_extras_pre
	build_launch_chain
	warn_launch_chain_issues
}

# run_game_launch — Full launch pipeline for Steam's %command% argv.
#
# Phases:
#   1. Recover stale state from prior crashes
#   2. Load layered config and detect game flags
#   3. Run preflight checks (skipped in BENCHMARK mode)
#   4. Pause VRAM hogs and register exit trap
#   5. Apply runtime tuning and build wrapper chain
#   6. Exec the final command (or print dry-run output)
run_game_launch() {
	local exit_code=0 duration=0
	local -a launch_args=("$@")

	steam_app_id=""
	detect_steam_app_id "$@"

	if [[ "$DRY_RUN" == "1" ]]; then
		prepare_launch_context "${steam_app_id:-}" || {
			echo "Dry run aborted: fix duplicate launch wrappers above." >&2
			exit 1
		}
		apply_override_proton launch_args
		warn_missing_tools
		apply_anticheat_guardrails
		debug "appid=${steam_app_id:-unknown} name=${steam_game_name:-unknown} native=$is_native eac=$is_anticheat type=${anticheat_type:-} engine=$game_engine_hint"
		print_dry_run "${launch_args[@]}"
		exit 0
	fi

	recover_stale_vram_state
	launch_start_time="$(date +%s)"

	load_launch_config
	apply_defaults
	apply_detected_defaults
	resolve_game_flags
	apply_auto_hardware_defaults
	parse_game_extra_args
	apply_override_proton launch_args

	debug "appid=${steam_app_id:-unknown} name=${steam_game_name:-unknown} native=$is_native eac=$is_anticheat type=${anticheat_type:-} engine=$game_engine_hint"

	if [[ "${BENCHMARK:-0}" != "1" ]]; then
		check_concurrent_launch
		check_vm_max_map_count
		check_shader_cache
		check_compatdata
		check_vram_available
		check_gpu_power
		check_gpu_vram_processes
		check_disk_space
	fi

	warn_missing_tools
	apply_anticheat_guardrails

	if [[ "${VRAM_HOGS:-0}" == "1" && "$DRY_RUN" != "1" ]]; then
		pause_vram_hogs
	fi

	# Every launch may apply host tuning, so teardown is unconditional.
	trap on_launch_exit EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM

	apply_network_tuning
	apply_pipewire_low_latency
	apply_cpu_performance
	apply_nvidia_power_mode
	apply_launch_env_tuning
	apply_proton_env
	apply_disk_tuning
	apply_hdr_tuning
	apply_malloc_allocator
	apply_launch_extras_pre
	apply_launch_extras_inject
	apply_launch_extras_wine
	build_launch_chain
	warn_launch_chain_issues || true

	playtime_record_start
	local hook_status=0
	run_pre_launch_cmd || hook_status=$?
	if (( hook_status != 0 )); then
		warn "PRE_LAUNCH_CMD failed (exit=$hook_status); launch aborted"
		exit_code=$hook_status
	else
		launch+=("${launch_args[@]}")
		[[ ${#game_extra_argv[@]} -gt 0 ]] && launch+=("${game_extra_argv[@]}")

		echo $$ > "$ACTIVE_LAUNCH_PID_FILE"
		if [[ "${steam_app_id:-}" =~ ^[0-9]+$ ]]; then
			printf '%s\n' "$steam_app_id" > "$ACTIVE_LAUNCH_APPID_FILE"
		else
			rm -f "$ACTIVE_LAUNCH_APPID_FILE"
		fi
		[[ "${LAUNCH_WATCHDOG:-0}" == "1" ]] && start_launch_watchdog $$

		"${launch[@]}" || exit_code=$?
		hook_status=0
		run_post_launch_cmd || hook_status=$?
		if (( hook_status != 0 )); then
			warn "POST_LAUNCH_CMD failed (exit=$hook_status)"
			(( exit_code == 0 )) && exit_code=$hook_status
		fi
	fi
	playtime_record_end
	inject_cleanup_launch_tracks "${steam_app_id:-}"
	crash_guess_maybe_prompt "$exit_code"
	duration=$(( $(date +%s) - launch_start_time ))
	log_launch_event "$exit_code" "$duration"
	exit "$exit_code"
}
