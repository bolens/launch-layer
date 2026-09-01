# shellcheck shell=bash
# lib/runtime/logging.sh — Launch log rotation, dry-run output.

[[ -n "${LAUNCHLAYER_RUNTIME_LOGGING_LOADED:-}" ]] && return 0
LAUNCHLAYER_RUNTIME_LOGGING_LOADED=1

# _rotate_launch_log_unlocked — Trim launch.log while the caller owns its lock.
_rotate_launch_log_unlocked() {
	local max_lines=${LAUNCH_LOG_MAX_LINES:-5000}
	[[ -f "$LAUNCH_LOG_FILE" ]] || return 0
	[[ "$max_lines" =~ ^[0-9]+$ && "$max_lines" -gt 0 ]] || return 0
	local count tmp
	count="$(wc -l < "$LAUNCH_LOG_FILE")"
	if (( count > max_lines )); then
		tmp="$(mktemp "$(dirname "$LAUNCH_LOG_FILE")/.launch-log.XXXXXX")" || return 1
		tail -n "$max_lines" "$LAUNCH_LOG_FILE" > "$tmp"
		mv -f "$tmp" "$LAUNCH_LOG_FILE"
	fi
}

# rotate_launch_log — Trim launch.log without racing another rotation or append.
rotate_launch_log() {
	local lock_fd
	[[ -f "$LAUNCH_LOG_FILE" ]] || return 0
	if command -v flock >/dev/null 2>&1; then
		exec {lock_fd}>"${LAUNCH_LOG_FILE}.lock" || return 1
		flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }
		_rotate_launch_log_unlocked
		local status=$?
		flock -u "$lock_fd" || true
		exec {lock_fd}>&-
		return "$status"
	fi
	_rotate_launch_log_unlocked
}

# log_launch_event — Append a structured line to launch.log.
log_launch_event() {
	local exit_code=${1:-} duration=${2:-0}
	local lock_fd=""
	mkdir -p "$STATE_DIR"
	if command -v flock >/dev/null 2>&1; then
		exec {lock_fd}>"${LAUNCH_LOG_FILE}.lock" || return 1
		flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }
		_rotate_launch_log_unlocked
	fi
	printf '%s appid=%s name=%q native=%s eac=%s benchmark=%s gamescope=%s vram_hogs=%s mangohud=%s x3d_cpus=%s duration=%ss exit=%s\n' \
		"$(timestamp_iso)" \
		"${steam_app_id:-unknown}" \
		"${steam_game_name:-unknown}" \
		"$is_native" \
		"$is_anticheat" \
		"${BENCHMARK:-0}" \
		"${GAMESCOPE:-0}" \
		"${VRAM_HOGS:-0}" \
		"$(launch_chain_uses_mangohud && echo 1 || echo 0)" \
		"${X3D_CPUS:-$(default_online_cpus)}" \
		"$duration" \
		"${exit_code:-}" \
		>> "$LAUNCH_LOG_FILE"
	if [[ -n "$lock_fd" ]]; then
		flock -u "$lock_fd" || true
		exec {lock_fd}>&-
	fi
}

# print_dry_run — Show resolved env and launch chain without executing.
print_dry_run() {
	echo "=== launchlayer dry run ==="
	echo "appid=${steam_app_id:-unknown} name=${steam_game_name:-unknown} native=$is_native eac=$is_anticheat"
	echo
	print_config_layers
	print_effective_config_summary
	echo
	echo "Environment (selected):"
	env | grep -E '^(PROTON_|DXVK_|VKD3D_|__GL_|__VK_|MANGOHUD|GAMESCOPE_|LD_PRELOAD|LD_BIND_NOW|ENABLE_HDR|ENABLE_VKBASALT|LFX|SteamDeck|vblank_mode|MESA_|RADV_)' | sort || true
	echo
	echo "Launch chain:"
	printf '  %q' "${launch[@]}" "$@" "${game_extra_argv[@]}"
	echo
}
