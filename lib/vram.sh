# shellcheck shell=bash
# shellcheck source=common.sh
# shellcheck source=runtime/logging.sh
# lib/vram.sh — VRAM-heavy service pause/resume and launch session cleanup.
#
# VRAM hogs (Sunshine, HyprWhspr, etc.) are stopped while a game runs so the
# GPU has headroom. A reference counter supports overlapping launches and a
# watchdog cleans up after force-quit crashes.

[[ -n "${LAUNCHLAYER_VRAM_LOADED:-}" ]] && return 0
LAUNCHLAYER_VRAM_LOADED=1

# get_vram_ref_count — Read the current pause refcount from disk.
get_vram_ref_count() {
	local count=0
	if [[ -f "$VRAM_REF_COUNT_FILE" ]]; then
		count="$(<"$VRAM_REF_COUNT_FILE")"
		[[ "$count" =~ ^[0-9]+$ ]] || count=0
	fi
	echo "$count"
}

# set_vram_ref_count — Persist the pause refcount (removes file when zero).
set_vram_ref_count() {
	local count=$1
	mkdir -p "$STATE_DIR"
	if (( count <= 0 )); then
		rm -f "$VRAM_REF_COUNT_FILE"
	else
		echo "$count" > "$VRAM_REF_COUNT_FILE"
	fi
}

# save_paused_vram_units — Write the list of stopped systemd units to state.
save_paused_vram_units() {
	mkdir -p "$STATE_DIR"
	: > "$VRAM_STATE_FILE"
	local unit
	for unit in "${paused_vram_units[@]}"; do
		printf '%s\n' "$unit" >> "$VRAM_STATE_FILE"
	done
}

# clear_paused_vram_units — Remove the paused-units state file.
clear_paused_vram_units() {
	rm -f "$VRAM_STATE_FILE"
}

# load_paused_vram_units_from_state — Repopulate paused_vram_units[] from disk.
load_paused_vram_units_from_state() {
	local unit
	paused_vram_units=()
	[[ -f "$VRAM_STATE_FILE" ]] || return 0
	while IFS= read -r unit || [[ -n "$unit" ]]; do
		[[ -z "$unit" ]] && continue
		paused_vram_units+=("$unit")
	done < "$VRAM_STATE_FILE"
}

# pause_vram_hogs — Stop VRAM_HOG_UNITS or SIGSTOP VRAM_HOG_PIDS while a game runs.
#
# Uses a refcount so nested/overlapping launches do not resume services early.
pause_vram_hogs() {
	local count unit pid
	count="$(get_vram_ref_count)"
	count=$((count + 1))
	set_vram_ref_count "$count"

	if (( count > 1 )); then
		debug "VRAM hogs already paused (ref=$count)"
		return 0
	fi

	if has_systemd_user; then
		paused_vram_units=()
		for unit in ${VRAM_HOG_UNITS}; do
			if systemctl --user is-active --quiet "$unit"; then
				systemctl --user stop "$unit" 2>/dev/null || true
				paused_vram_units+=("$unit")
				debug "paused $unit"
			fi
		done
		save_paused_vram_units
		return 0
	fi

	if [[ -n "${VRAM_HOG_PIDS:-}" ]]; then
		mkdir -p "$STATE_DIR"
		: > "$VRAM_PID_STATE_FILE"
		for pid in ${VRAM_HOG_PIDS}; do
			[[ "$pid" =~ ^[0-9]+$ ]] || continue
			kill -0 "$pid" 2>/dev/null || continue
			kill -STOP "$pid" 2>/dev/null || continue
			printf '%s\n' "$pid" >> "$VRAM_PID_STATE_FILE"
			debug "SIGSTOP pid $pid"
		done
		return 0
	fi

	debug "VRAM_HOGS=1 but systemd user session is unavailable and VRAM_HOG_PIDS is unset — hogs not paused"
}

# resume_vram_hogs — Decrement refcount and restart paused units when it hits zero.
resume_vram_hogs() {
	local count unit
	count="$(get_vram_ref_count)"
	(( count > 0 )) && count=$((count - 1))
	set_vram_ref_count "$count"

	if (( count > 0 )); then
		debug "VRAM hogs still needed (ref=$count)"
		return 0
	fi

	load_paused_vram_units_from_state
	for unit in "${paused_vram_units[@]}"; do
		systemctl --user start "$unit" 2>/dev/null || true
		debug "resumed $unit"
	done
	paused_vram_units=()
	clear_paused_vram_units
	resume_vram_pids
}

# resume_vram_pids — SIGCONT processes stopped via VRAM_HOG_PIDS.
resume_vram_pids() {
	local pid
	[[ -f "$VRAM_PID_STATE_FILE" ]] || return 0
	while IFS= read -r pid || [[ -n "$pid" ]]; do
		[[ "$pid" =~ ^[0-9]+$ ]] || continue
		kill -CONT "$pid" 2>/dev/null || true
		debug "SIGCONT pid $pid"
	done < "$VRAM_PID_STATE_FILE"
	rm -f "$VRAM_PID_STATE_FILE"
}

# resume_vram_hogs_force — Unconditionally restart all paused units (recovery).
resume_vram_hogs_force() {
	set_vram_ref_count 0
	load_paused_vram_units_from_state
	local unit
	for unit in "${paused_vram_units[@]}"; do
		systemctl --user start "$unit" 2>/dev/null || true
		debug "resumed $unit"
	done
	paused_vram_units=()
	clear_paused_vram_units
	resume_vram_pids
}

# recover_stale_vram_state — Fix orphaned pause state after crashes or force-quit.
recover_stale_vram_state() {
	local ref active_pid
	ref="$(get_vram_ref_count)"

	# Active launch PID file exists but the process is gone → full cleanup.
	if [[ -f "$ACTIVE_LAUNCH_PID_FILE" ]]; then
		active_pid="$(<"$ACTIVE_LAUNCH_PID_FILE")"
		if [[ "$active_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$active_pid" 2>/dev/null; then
			warn "recovering after force-quit (dead launch session pid=$active_pid)"
			cleanup_stale_launch "$active_pid"
			return 0
		fi
	fi

	# Paused units/pids on disk but refcount is zero → stale state.
	[[ -f "$VRAM_STATE_FILE" || -f "$VRAM_PID_STATE_FILE" ]] || return 0
	if (( ref == 0 )); then
		warn "found stale paused-vram state; resuming services"
		resume_vram_hogs_force
	fi
}

# cleanup_stale_launch — Tear down watchdog + VRAM state for a dead launch session.
#
# Optional expected_pid guards against cleaning up a newer concurrent session.
cleanup_stale_launch() {
	local expected_pid=${1:-} active_pid=""
	stop_launch_watchdog

	[[ -f "$ACTIVE_LAUNCH_PID_FILE" ]] && active_pid="$(<"$ACTIVE_LAUNCH_PID_FILE")"
	if [[ -n "$expected_pid" && -n "$active_pid" && "$active_pid" != "$expected_pid" ]]; then
		debug "cleanup skipped: active session $active_pid != $expected_pid"
		return 0
	fi
	if [[ -n "$expected_pid" ]] && kill -0 "$expected_pid" 2>/dev/null; then
		debug "cleanup skipped: launch pid $expected_pid still running"
		return 0
	fi

	rm -f "$ACTIVE_LAUNCH_PID_FILE"
	restore_nvidia_power_mode
	declare -F restore_pipewire_low_latency >/dev/null 2>&1 && restore_pipewire_low_latency
	declare -F restore_runtime_tuning >/dev/null 2>&1 && restore_runtime_tuning
	if [[ -f "$VRAM_STATE_FILE" || -f "$VRAM_PID_STATE_FILE" ]] || (( $(get_vram_ref_count) > 0 )); then
		resume_vram_hogs_force
	fi
}

# stop_launch_watchdog — Kill the background cleanup watchdog if one is running.
stop_launch_watchdog() {
	local pid=""
	[[ -f "$WATCHDOG_PID_FILE" ]] || return 0
	pid="$(<"$WATCHDOG_PID_FILE")"
	rm -f "$WATCHDOG_PID_FILE"
	[[ "$pid" =~ ^[0-9]+$ ]] || return 0
	kill "$pid" 2>/dev/null || true
}

# start_launch_watchdog — Monitor launch_pid and trigger cleanup when it exits.
#
# Prefers systemd-run for automatic unit cleanup; falls back to setsid+nohup.
start_launch_watchdog() {
	local launch_pid=$1 script_path watchdog_cmd pid
	script_path="$(realpath_portable "${LAUNCHLAYER_MAIN_SCRIPT:-$0}" 2>/dev/null || echo "${LAUNCHLAYER_MAIN_SCRIPT:-$0}")"
	watchdog_cmd="
		while kill -0 ${launch_pid} 2>/dev/null; do sleep 3; done
		sleep 1
		exec $(printf '%q' "$script_path") --cleanup-stale-launch ${launch_pid}
	"
	stop_launch_watchdog
	if command -v systemd-run >/dev/null 2>&1 \
		&& systemd-run --user --quiet --collect \
			--unit="launchlayer-watch-${launch_pid}" \
			--description="Steam launch cleanup watchdog" \
			bash -c "$watchdog_cmd" >/dev/null 2>&1; then
		debug "launch watchdog started via systemd-run (pid=$launch_pid)"
		return 0
	fi
	nohup setsid bash -c "$watchdog_cmd" >/dev/null 2>&1 &
	pid=$!
	echo "$pid" > "$WATCHDOG_PID_FILE"
	debug "launch watchdog started via setsid (watchdog pid=$pid)"
}

# on_launch_exit — EXIT/INT/TERM trap handler for normal launch teardown.
on_launch_exit() {
	stop_launch_watchdog
	restore_nvidia_power_mode
	restore_pipewire_low_latency
	restore_runtime_tuning
	rm -f "$ACTIVE_LAUNCH_PID_FILE"
	[[ "${VRAM_HOGS:-0}" == "1" ]] && resume_vram_hogs
}
