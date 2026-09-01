# shellcheck shell=bash
# lib/common.sh — Shared paths, runtime state, and logging helpers.
#
# Sourced by launchlayer after CONFIG_DIR is set.
# Expects: CONFIG_DIR (absolute path to the config root).
# Globals here are consumed by other lib/*.sh modules (SC2034 disabled).

: "${CONFIG_DIR:?CONFIG_DIR must be set before sourcing lib/common.sh}"

# Prevent double-sourcing when the watchdog re-invokes the main script.
[[ -n "${LAUNCHLAYER_COMMON_LOADED:-}" ]] && return 0
LAUNCHLAYER_COMMON_LOADED=1

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------

LAUNCHD_DIR="$CONFIG_DIR/launch.d"
PROFILES_DIR="$LAUNCHD_DIR/profiles"
GAMES_DIR="${LAUNCHLAYER_GAMES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/launchlayer/games}"

# launchlayer_share_dir — Shipped templates, completions, systemd units, sysctl drop-ins.
# Prefer CONFIG_DIR (install/repo root). When tests point CONFIG_DIR at a temp tree,
# fall back to LIB_DIR/SCRIPT_DIR so packageless fixtures still find share data.
launchlayer_share_dir() {
	local candidate
	for candidate in \
		"$CONFIG_DIR/share/launchlayer" \
		"${LIB_DIR:+$LIB_DIR/../share/launchlayer}" \
		"${SCRIPT_DIR:+$SCRIPT_DIR/share/launchlayer}"; do
		[[ -n "$candidate" ]] || continue
		if [[ -d "$candidate" ]]; then
			# Normalize .. components when falling back via LIB_DIR.
			(cd "$candidate" && pwd)
			return 0
		fi
	done
	printf '%s/share/launchlayer' "$CONFIG_DIR"
}

# sysctl_dropin_source — Repo path to elasticsearch.conf sysctl drop-in.
sysctl_dropin_source() {
	printf '%s/sysctl/elasticsearch.conf' "$(launchlayer_share_dir)"
}

# STEAM_ROOT resolved in lib/platform/profiles.sh unless already exported and valid.
: "${STEAM_ROOT:=}"

# _migrate_legacy_dir — Race-safe move of one pre-rename directory.
_migrate_legacy_dir() {
	local old_dir=$1 new_dir=$2
	[[ -d "$old_dir" && ! -e "$new_dir" ]] || return 0
	if mv "$old_dir" "$new_dir" 2>/dev/null; then
		return 0
	fi
	# Another LaunchLayer process may have completed the same migration.
	[[ ! -e "$old_dir" && -e "$new_dir" ]]
}

# migrate_legacy_install_paths — Move pre-rename config/state dirs on startup.
migrate_legacy_install_paths() {
	local old_config new_config old_state new_state status=0
	old_config="${XDG_CONFIG_HOME:-$HOME/.config}/steam-launch"
	new_config="${XDG_CONFIG_HOME:-$HOME/.config}/launchlayer"
	old_state="${XDG_STATE_HOME:-$HOME/.local/state}/steam-launch"
	new_state="${XDG_STATE_HOME:-$HOME/.local/state}/launchlayer"
	_migrate_legacy_dir "$old_config" "$new_config" || status=1
	_migrate_legacy_dir "$old_state" "$new_state" || status=1
	return "$status"
}

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/launchlayer"

# Proton/Wine stability target; overrides elasticsearch package sysctl (262144).
LAUNCHLAYER_VM_MAX_MAP_COUNT_DEFAULT=2147483642

# Persistent state files (survive across game sessions).
VRAM_STATE_FILE="$STATE_DIR/paused-vram-units"
VRAM_PID_STATE_FILE="$STATE_DIR/paused-vram-pids"
VRAM_REF_COUNT_FILE="$STATE_DIR/vram-hog-refcount"
ACTIVE_LAUNCH_PID_FILE="$STATE_DIR/active-launch.pid"
WATCHDOG_PID_FILE="$STATE_DIR/launch-watchdog.pid"
LAUNCH_LOG_FILE="$STATE_DIR/launch.log"
X3D_CPUS_CACHE_FILE="$STATE_DIR/x3d-cpus"
X3D_CPUS_META_FILE="$STATE_DIR/x3d-cpus.meta"

# ---------------------------------------------------------------------------
# Per-launch mutable state (reset each game launch)
# ---------------------------------------------------------------------------

declare -g -A config_loaded=()
declare -g -A config_key_sources=()
declare -g -a config_layers=()
declare -g -a paused_vram_units=()
declare -g -a launch=()
declare -g -a game_extra_argv=()

DRY_RUN=0
LAUNCH_QUIET=0
LAUNCH_VERBOSE=0
is_native=0
is_anticheat=0
anticheat_type=""
game_engine_hint=""
steam_app_id=""
steam_game_name=""
launch_start_time=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# debug — Print when DEBUG=1, LAUNCH_VERBOSE=1, or --verbose was passed.
debug() {
	if [[ "${DEBUG:-0}" == "1" || "${LAUNCH_VERBOSE:-0}" == "1" ]]; then
		echo "[launchlayer] $*" >&2
	fi
}

# warn — Non-fatal warning to stderr (suppressed when LAUNCH_QUIET=1).
warn() {
	[[ "${LAUNCH_QUIET:-0}" == "1" ]] && return 0
	echo "[launchlayer] warning: $*" >&2
}
