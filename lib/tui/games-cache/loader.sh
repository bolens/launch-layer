# shellcheck shell=bash
# lib/tui/games-cache/loader.sh — Background list-games loader and fzf chrome refresh.

[[ -n "${LAUNCHLAYER_TUI_GAMES_CACHE_LOADER_LOADED:-}" ]] && return 0
LAUNCHLAYER_TUI_GAMES_CACHE_LOADER_LOADED=1
# tui_games_cache_watch_start — Animate chrome files and pulse SIGWINCH while loader runs.
# Optional arg: process group to signal (defaults to caller shell $$).
tui_games_cache_watch_start() {
	local pgid=${1:-$$}
	tui_games_cache_watch_stop
	[[ -t 0 || -t 1 ]] || return 0
	(
		while tui_games_cache_busy; do
			tui_games_cache_write_chrome
			kill -WINCH -"$pgid" 2>/dev/null || true
			sleep 0.12
		done
		tui_games_cache_write_chrome
		tui_games_cache_paths
		[[ -d "$TUI_GAMES_CACHE_DIR" ]] && touch "${TUI_GAMES_CACHE_DIR}/refresh-list"
		kill -WINCH -"$pgid" 2>/dev/null || true
	) &
	TUI_GAMES_CACHE_WATCH_PID=$!
}

# tui_games_cache_watch_stop — Stop the fzf refresh watcher.
tui_games_cache_watch_stop() {
	if [[ -n "${TUI_GAMES_CACHE_WATCH_PID:-}" ]]; then
		kill "${TUI_GAMES_CACHE_WATCH_PID}" 2>/dev/null || true
		unset TUI_GAMES_CACHE_WATCH_PID
	fi
}

# tui_games_cache_spinner_frame — Current braille spinner frame (sub-second rotation).
tui_games_cache_spinner_frame() {
	local i now_ms
	if [[ "${TUI_SPINNER:-1}" == "0" || "${TUI_TEXT_STATUS:-0}" == "1" ]]; then
		printf '%s' '…'
		return 0
	fi
	now_ms="$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")"
	i=$((now_ms / 120 % ${#TUI_SPINNER_FRAMES[@]}))
	printf '%s' "${TUI_SPINNER_FRAMES[i]}"
}

# tui_games_cache_resolve_main_script — Path to launchlayer for background loader invocations.
tui_games_cache_resolve_main_script() {
	local script="${LAUNCHLAYER_MAIN_SCRIPT:-}"
	if [[ -z "$script" ]]; then
		script="$(command -v launchlayer 2>/dev/null || true)"
	fi
	[[ -n "$script" ]] || return 1
	printf '%s' "$script"
}

# tui_games_cache_spawn_loader — Background --list-games; atomically replace lines on success.
tui_games_cache_spawn_loader() {
	local loader main_script main_q config_q lines_q status_q pid_q log_q refresh_q
	tui_games_cache_paths
	mkdir -p "$TUI_GAMES_CACHE_DIR"
	if tui_games_cache_loader_alive; then
		return 0
	fi
	main_script="$(tui_games_cache_resolve_main_script)" || {
		printf 'error\n' > "$TUI_GAMES_CACHE_STATUS"
		return 1
	}
	if ! tui_games_cache_has_lines; then
		printf 'loading\n' > "$TUI_GAMES_CACHE_STATUS"
	fi
	main_q="$(printf '%q' "$main_script")"
	config_q="$(printf '%q' "$CONFIG_DIR")"
	lines_q="$(printf '%q' "$TUI_GAMES_CACHE_FILE")"
	status_q="$(printf '%q' "$TUI_GAMES_CACHE_STATUS")"
	pid_q="$(printf '%q' "$TUI_GAMES_CACHE_PID_FILE")"
	log_q="$(printf '%q' "${TUI_GAMES_CACHE_DIR}/loader.log")"
	refresh_q="$(printf '%q' "${TUI_GAMES_CACHE_DIR}/refresh-list")"
	loader="${TUI_GAMES_CACHE_DIR}/loader.sh"
	cat > "$loader" <<EOF
#!/usr/bin/env bash
set -euo pipefail
main=$main_q
config_dir=$config_q
lines=$lines_q
status=$status_q
pidfile=$pid_q
log=$log_q
refresh=$refresh_q
export CONFIG_DIR="\$config_dir"
export LAUNCHLAYER_CONFIG_DIR="\${LAUNCHLAYER_CONFIG_DIR:-\$config_dir}"
work="\${lines}.work.\$\$"
finish() {
	rm -f "\$work"
	rm -f "\${lines}.new"
	if [[ -f "\$pidfile" ]] && [[ "\$(<"\$pidfile")" == "\$\$" ]]; then
		rm -f "\$pidfile"
	fi
	touch "\$refresh"
}
trap finish EXIT
if LAUNCH_QUIET=1 "\$main" --list-games 2>>"\$log" | tail -n +2 > "\$work"; then
	if [[ ! -f "\$pidfile" ]] || [[ "\$(<"\$pidfile")" != "\$\$" ]]; then
		exit 0
	fi
	mv -f "\$work" "\$lines"
	printf 'ready\n' > "\$status"
else
	rm -f "\$work"
	if [[ -s "\$lines" ]]; then
		printf 'ready\n' > "\$status"
	else
		printf 'error\n' > "\$status"
	fi
	exit 1
fi
EOF
	chmod +x "$loader"
	if command -v setsid >/dev/null 2>&1; then
		setsid "$loader" >>"${TUI_GAMES_CACHE_DIR}/loader.log" 2>&1 &
	else
		nohup "$loader" >>"${TUI_GAMES_CACHE_DIR}/loader.log" 2>&1 &
	fi
	disown -h "$!" 2>/dev/null || true
	printf '%s\n' "$!" > "$TUI_GAMES_CACHE_PID_FILE"
}

# tui_games_cache_start — Ensure a load is running when no lines exist yet.
tui_games_cache_start() {
	tui_games_cache_paths
	mkdir -p "$TUI_GAMES_CACHE_DIR"
	tui_games_cache_reconcile
	tui_games_cache_write_chrome
	if tui_games_cache_loader_alive; then
		return 0
	fi
	if ! tui_games_cache_has_lines; then
		tui_games_cache_spawn_loader
	fi
}

# tui_games_cache_bootstrap — TUI entry: use persisted cache immediately; refresh in background.
tui_games_cache_bootstrap() {
	tui_games_cache_paths
	mkdir -p "$TUI_GAMES_CACHE_DIR"
	tui_games_cache_reconcile
	if tui_games_cache_has_lines && [[ "$(tui_games_cache_status)" != ready ]]; then
		printf 'ready\n' > "$TUI_GAMES_CACHE_STATUS"
	fi
	tui_games_cache_write_chrome
	if tui_games_cache_loader_alive; then
		return 0
	fi
	tui_games_cache_spawn_loader
}

# tui_games_cache_chrome_bind_paths — Quoted cat commands for fzf transform binds.
tui_games_cache_chrome_bind_paths() {
	local header_q footer_q
	tui_games_cache_paths
	header_q="$(printf '%q' "$TUI_GAMES_CACHE_CHROME_HEADER")"
	footer_q="$(printf '%q' "$TUI_GAMES_CACHE_CHROME_FOOTER")"
	TUI_GAMES_CACHE_CHROME_HEADER_BIND="cat ${header_q}"
	TUI_GAMES_CACHE_CHROME_FOOTER_BIND="cat ${footer_q}"
}

# tui_games_cache_write_chrome — Write fzf header/footer text files (fast reload target).
tui_games_cache_write_chrome() {
	tui_games_cache_reconcile
	tui_games_cache_paths
	mkdir -p "$TUI_GAMES_CACHE_DIR"
	case "${TUI_GAMES_CACHE_CHROME_MODE:-menu}" in
		picker)
			tui_games_picker_header >"$TUI_GAMES_CACHE_CHROME_HEADER"
			tui_games_picker_footer >"$TUI_GAMES_CACHE_CHROME_FOOTER"
			;;
		*)
			tui_games_menu_header >"$TUI_GAMES_CACHE_CHROME_HEADER"
			tui_games_menu_footer >"$TUI_GAMES_CACHE_CHROME_FOOTER"
			;;
	esac
}

# tui_games_cache_wait — Block until cache is ready (spinner on stderr).
tui_games_cache_wait() {
	tui_games_cache_start
	if tui_games_cache_ready; then
		return 0
	fi
	tui_spinner_capture "Loading installed games…" tui_games_cache_wait_core
}

# tui_games_cache_wait_core — Poll until status is ready or error.
tui_games_cache_wait_core() {
	while tui_games_cache_loading; do
		sleep 0.08
	done
	if tui_games_cache_ready; then
		return 0
	fi
	printf 'Failed to load installed games.\n' >&2
	return 1
}

# tui_games_cache_count — Game count for footers (non-blocking, honors active filter).
tui_games_cache_count() {
	if tui_games_cache_has_lines; then
		tui_games_cache_paths
		tui_games_cache_apply_filter <"$TUI_GAMES_CACHE_FILE" | wc -l | tr -d '[:space:]'
	elif tui_games_cache_busy; then
		printf '…'
	else
		printf '0'
	fi
}

# tui_games_cache_lines — Print cached lines when ready (filtered).
# Implemented in pickers.sh (loads later) to normalize legacy rows; stub until then.
if [[ -z "${LAUNCHLAYER_TUI_PICKERS_LOADED:-}" ]]; then
	tui_games_cache_lines() {
		tui_games_cache_paths
		tui_games_cache_has_lines || return 1
		tui_games_cache_apply_filter <"$TUI_GAMES_CACHE_FILE"
	}
fi
