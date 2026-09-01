# shellcheck shell=bash
# lib/commands/dispatch-launch.sh

[[ -n "${LAUNCHLAYER_DISPATCH_LAUNCH_LOADED:-}" ]] && return 0
LAUNCHLAYER_DISPATCH_LAUNCH_LOADED=1

# dispatch_launch_subcommand — Return 0 when verb is handled.
dispatch_launch_subcommand() {
	local verb=${1:-}
	shift || true
	case "$verb" in
		--run-maintenance)
			[[ $# -eq 0 ]] || {
				echo "Usage: $(cli_basename) --run-maintenance" >&2
				return 2
			}
			local maintenance_status=0
			cleanup_stale_launch || maintenance_status=$?
			cache_report 10 both "" 0 || maintenance_status=$?
			return "$maintenance_status"
			;;
		--pause-vram-hogs)
			pause_vram_hogs
			echo "Paused VRAM-heavy services (ref=$(get_vram_ref_count))"
			;;
		--resume-vram-hogs)
			resume_vram_hogs_force
			rm -f "$ACTIVE_LAUNCH_PID_FILE" "$ACTIVE_LAUNCH_APPID_FILE"
			stop_launch_watchdog
			echo "Resumed paused VRAM-heavy services."
			;;
		--cleanup-stale-launch)
			cleanup_stale_launch "${1:-}"
			;;
		--status)
			load_profile_config
			load_config_file "$LAUNCHD_DIR/default.env" 0
			apply_defaults
			local status_appid="" status_json=0 arg
			for arg in "$@"; do
				case "$arg" in
					--json) status_json=1 ;;
					*) [[ -z "$status_appid" ]] && status_appid=$arg ;;
				esac
			done
			if [[ -n "$status_appid" && ! "$status_appid" =~ ^[0-9]+$ ]]; then
				status_appid="$(resolve_appid_arg "$status_appid")" || return $?
			fi
			show_status "$status_appid" "$status_json"
			;;
		--show-cpu-topology)
			load_config_file "$LAUNCHD_DIR/default.env" 0
			apply_defaults
			show_cpu_topology
			;;
		--cache-report)
			local min_gb=5 mode=both grep_pattern="" cache_json=0
			while [[ $# -gt 0 ]]; do
				case "$1" in
					--min-gb) min_gb=${2:-5}; shift 2 ;;
					--grep) grep_pattern=${2:-}; shift 2 ;;
					--shader-only) mode=shader; shift ;;
					--compat-only) mode=compat; shift ;;
					--json) cache_json=1; shift ;;
					*) shift ;;
				esac
			done
			cache_report "$min_gb" "$mode" "$grep_pattern" "$cache_json"
			;;
		--launch-stats)
			local stats_query="" stats_json=0 arg
			for arg in "$@"; do
				case "$arg" in
					--json) stats_json=1 ;;
					*) [[ -z "$stats_query" ]] && stats_query=$arg ;;
				esac
			done
			launch_stats "$stats_query" "$stats_json"
			;;
		*)
			return 1
			;;
	esac
}
