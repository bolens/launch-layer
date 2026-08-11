# shellcheck shell=bash
# lib/cli.sh — CLI presentation: help, version, usage hints, unknown-subcommand suggestions.

[[ -n "${LAUNCHLAYER_CLI_LOADED:-}" ]] && return 0
LAUNCHLAYER_CLI_LOADED=1

# Bump when user-visible CLI behavior or subcommands change materially.
LAUNCHLAYER_VERSION=0.12.0

# All utility subcommands (for completion parity and typo suggestions).
LAUNCHLAYER_SUBCOMMANDS=(
	--help -h
	--version -V
	--doctor
	--setup
	--detect-environment
	--detect-defaults
	--write-local-config
	--completions
	--install-systemd
	--sysctl
	--status
	--show-cpu-topology
	--list-games
	--init-appid
	--bulk-set-include
	--init-unconfigured
	--prune-uninstalled
	--export-config
	--backup-config
	--import-config
	--restore-backup
	--prune-backups
	--run-scheduled-backup
	--backup-timer
	--backup-prefs
	--tui-prefs
	--tui-game-preview
	--tui-game-preview-line
	--tui-picker-appid
	--tui-help
	--tui-panel
	--tui-games-menu-reload
	--tui-games-menu-footer
	--tui-games-menu-header
	--tui-games-menu-resize-reload
	--tui-games-picker-reload
	--tui-games-picker-footer
	--tui-games-picker-header
	--tui-games-picker-resize-reload
	--show-config
	--edit-appid
	--paths
	--validate-config
	--suggest-config
	--scan-anticheat
	--scan-detections
	--hub-fingerprint
	--hub-publish
	--hub-update
	--hub-delete
	--hub-recommend
	--hub-apply
	--hub-history
	--hub-search
	--hub-prefs
	--cache-report
	--launch-stats
	--dry-run
	--pause-vram-hogs
	--resume-vram-hogs
	--cleanup-stale-launch
	--tui
)

# cli_basename — Script filename for usage strings.
cli_basename() {
	basename "${LAUNCHLAYER_MAIN_SCRIPT:-launchlayer}"
}

# cli_parse_global_flags — Strip leading --quiet/-q and --verbose/-v from argv.
# Sets LAUNCH_QUIET / LAUNCH_VERBOSE / DEBUG; prints remaining args one per line.
cli_parse_global_flags() {
	local arg
	LAUNCH_QUIET=${LAUNCH_QUIET:-0}
	LAUNCH_VERBOSE=${LAUNCH_VERBOSE:-0}
	[[ "${LAUNCHLAYER_QUIET:-${STEAM_LAUNCH_QUIET:-0}}" == "1" ]] && LAUNCH_QUIET=1
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--quiet|-q) LAUNCH_QUIET=1; shift ;;
			--verbose|-v) LAUNCH_VERBOSE=1; DEBUG=1; shift ;;
			*) break ;;
		esac
	done
	while [[ $# -gt 0 ]]; do
		printf '%s\n' "$1"
		shift
	done
}

# cli_scan_progress_enabled — True when stderr is a TTY and scans may show progress.
cli_scan_progress_enabled() {
	[[ -t 2 && "${LAUNCH_QUIET:-0}" != "1" && "${CLI_JSON_OUTPUT:-0}" != "1" ]]
}

# cli_scan_progress_begin — Optional progress label before manifest iteration.
cli_scan_progress_begin() {
	local label=${1:-Scanning Steam library}
	CLI_SCAN_LABEL=$label
	CLI_SCAN_COUNT=0
	cli_scan_progress_enabled || return 0
	printf '%s…\n' "$CLI_SCAN_LABEL" >&2
}

# cli_scan_progress_tick — Increment scan counter and refresh progress line.
cli_scan_progress_tick() {
	((CLI_SCAN_COUNT++)) || true
	cli_scan_progress_enabled || return 0
	printf '\r%s (%d games scanned)' "$CLI_SCAN_LABEL" "$CLI_SCAN_COUNT" >&2
}

# cli_scan_progress_end — Finish progress line after manifest iteration.
cli_scan_progress_end() {
	cli_scan_progress_enabled || return 0
	printf '\r%s (%d games scanned)\n' "$CLI_SCAN_LABEL" "${CLI_SCAN_COUNT:-0}" >&2
}

# cli_edit_distance — Levenshtein distance between two strings (bash-only).
cli_edit_distance() {
	local a=$1 b=$2
	local -i i j len_a=${#a} len_b=${#b}
	local -i cost=0
	local -a prev curr

	if (( len_a == 0 )); then echo "$len_b"; return; fi
	if (( len_b == 0 )); then echo "$len_a"; return; fi

	prev=()
	for ((i = 0; i <= len_b; i++)); do prev[i]=$i; done

	for ((i = 1; i <= len_a; i++)); do
		curr[0]=$i
		for ((j = 1; j <= len_b; j++)); do
			if [[ ${a:i-1:1} == "${b:j-1:1}" ]]; then
				cost=${prev[j-1]}
			else
				cost=$(( prev[j-1] + 1 ))
				(( curr[j-1] + 1 < cost )) && cost=$(( curr[j-1] + 1 ))
				(( prev[j] + 1 < cost )) && cost=$(( prev[j] + 1 ))
			fi
			curr[j]=$cost
		done
		prev=("${curr[@]}")
	done
	echo "${prev[len_b]}"
}

# cli_suggest_subcommand — Print closest subcommand matches for a typo.
cli_suggest_subcommand() {
	local input=$1
	local cmd dist best_dist=99
	local -a suggestions=()

	[[ "$input" == --* ]] || return 1

	for cmd in "${LAUNCHLAYER_SUBCOMMANDS[@]}"; do
		dist="$(cli_edit_distance "$input" "$cmd")"
		if (( dist <= 3 && dist < best_dist )); then
			suggestions=("$cmd")
			best_dist=$dist
		elif (( dist == best_dist && dist <= 3 )); then
			suggestions+=("$cmd")
		fi
	done

	((${#suggestions[@]})) || return 1
	printf '%s\n' "${suggestions[@]}"
}

# cli_is_known_subcommand — True when verb is a registered utility flag.
cli_is_known_subcommand() {
	local verb=$1 cmd
	for cmd in "${LAUNCHLAYER_SUBCOMMANDS[@]}"; do
		[[ "$cmd" == "$verb" ]] && return 0
	done
	return 1
}

# cli_unknown_subcommand — Error message for unrecognized utility flags.
cli_unknown_subcommand() {
	local verb=$1
	local -a suggestions=()
	local suggestion

	echo "launchlayer: unknown subcommand: $verb" >&2
	mapfile -t suggestions < <(cli_suggest_subcommand "$verb" || true)
	if ((${#suggestions[@]})); then
		if ((${#suggestions[@]} == 1)); then
			echo "Did you mean '${suggestions[0]}'?" >&2
		else
			echo "Did you mean one of:" >&2
			for suggestion in "${suggestions[@]}"; do
				echo "  $suggestion" >&2
			done
		fi
	fi
	echo "Run '$(cli_basename) --help' for usage." >&2
}
