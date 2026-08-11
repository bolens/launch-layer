# shellcheck shell=bash
# Shared helpers for LaunchLayer bats tests.

launchlayer_root() {
	if [[ -n "${CONFIG_DIR:-}" ]]; then
		printf '%s\n' "$CONFIG_DIR"
		return
	fi
	local helpers_dir
	helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	printf '%s\n' "$(cd "$helpers_dir/.." && pwd)"
}

launchlayer_script() {
	printf '%s\n' "$(launchlayer_root)/launchlayer"
}

# seed_fake_steam_game — Write a minimal appmanifest + installdir for tests.
seed_fake_steam_game() {
	local steam_root=$1 appid=$2 name=$3 installdir
	installdir=${4:-TestGame${appid}}
	mkdir -p "$steam_root/steamapps/common/$installdir"
	cat > "$steam_root/steamapps/appmanifest_${appid}.acf" <<EOF
"AppState"
{
	"appid"		"$appid"
	"name"		"$name"
	"installdir"		"$installdir"
}
EOF
}

# fake_steam_root — Temp Steam root with one installed game.
fake_steam_root() {
	local appid=$1 name=$2 installdir=${3:-}
	local tmp
	tmp="$(mktemp -d)"
	seed_fake_steam_game "$tmp" "$appid" "$name" "${installdir:-TestGame${appid}}"
	printf '%s\n' "$tmp"
}

temp_config_dir() {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/launch.d/presets" "$tmp/games"
	printf '%s\n' 'GAMEMODE=1' > "$tmp/launch.d/default.env"
	printf '%s\n' 'MANGOHUD=0' > "$tmp/launch.d/presets/standard.env"
	printf '%s\n' "$tmp"
}

# temp_state_dir — Isolated XDG state for unit tests touching STATE_DIR.
temp_state_dir() {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/state/launchlayer"
	printf '%s\n' "$tmp"
}

# _source_lib_module — Source one lib module or modular subtree.
_source_lib_module() {
	local root=$1 module=$2
	case "$module" in
		platform) launchlayer_source_platform ;;
		hardware) launchlayer_source_hardware ;;
		inspect) launchlayer_source_inspect ;;
		prefs) launchlayer_source_prefs ;;
		completions) launchlayer_source_completions ;;
		setup) launchlayer_source_setup ;;
		commands) launchlayer_source_commands ;;
		hub) launchlayer_source_hub ;;
		runtime) launchlayer_source_runtime ;;
		steam) launchlayer_source_steam ;;
		cli) launchlayer_source_cli ;;
		*)
			# shellcheck source=/dev/null
			source "$root/lib/${module}.sh"
			;;
	esac
}

# stop_hub_mock_server — Stop background hub-mock-server.py if running.
stop_hub_mock_server() {
	[[ -n "${HUB_MOCK_PID:-}" ]] || return 0
	kill "$HUB_MOCK_PID" 2>/dev/null || true
	wait "$HUB_MOCK_PID" 2>/dev/null || true
	unset HUB_MOCK_PID HUB_MOCK_URL HUB_MOCK_PORT
}

# start_hub_mock_server — Start hub-mock-server.py; sets HUB_MOCK_URL and HUB_MOCK_PID.
# Usage: start_hub_mock_server [token] [open=0|1]
start_hub_mock_server() {
	local token=${1:-test-secret} open=${2:-0}
	local fixtures_dir script port_file args=()
	fixtures_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"
	script="$fixtures_dir/hub-mock-server.py"
	[[ -f "$script" ]] || {
		echo "missing hub mock server: $script" >&2
		return 1
	}
	stop_hub_mock_server
	args=(--token "$token")
	[[ "$open" == "1" ]] && args+=(--open)
	port_file="$(mktemp)"
	python3 "$script" "${args[@]}" >"$port_file" &
	HUB_MOCK_PID=$!
	local i=0
	while (( i < 50 )); do
		[[ -s "$port_file" ]] && break
		sleep 0.05
		i=$((i + 1))
	done
	HUB_MOCK_PORT="$(tr -d '[:space:]' <"$port_file")"
	rm -f "$port_file"
	[[ "$HUB_MOCK_PORT" =~ ^[0-9]+$ ]] || {
		stop_hub_mock_server
		echo "hub mock server failed to start" >&2
		return 1
	}
	HUB_MOCK_URL="http://127.0.0.1:${HUB_MOCK_PORT}"
	export HUB_MOCK_PID HUB_MOCK_URL HUB_MOCK_PORT
}

# write_hub_conf — Write a minimal hub.conf in a temp XDG config dir.
write_hub_conf() {
	local xdg=$1 hub_url=$2 publish_token=${3:-} fingerprint_level=${4:-minimal}
	mkdir -p "$xdg/launchlayer"
	cat >"$xdg/launchlayer/hub.conf" <<EOF
hub_url=${hub_url}
publish_token=${publish_token}
machine_label=test-machine
fingerprint_level=${fingerprint_level}
EOF
}

# bats_unit_setup — Common setup for test/unit/*.bats.
bats_unit_setup() {
	source "$BATS_TEST_DIRNAME/../helpers.bash"
	CONFIG_DIR="$(launchlayer_root)"
	export CONFIG_DIR
}

# bats_integration_setup — Common setup for test/integration/*.bats.
bats_integration_setup() {
	source "$BATS_TEST_DIRNAME/../helpers.bash"
	BATS_SAVED_HOME="${HOME:-}"
	BATS_SAVED_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
	BATS_SAVED_XDG_STATE_HOME="${XDG_STATE_HOME:-}"
	BATS_TEST_STATE_HOME="$(mktemp -d)"
	export XDG_STATE_HOME="$BATS_TEST_STATE_HOME"
	SCRIPT="$(launchlayer_script)"
	REPO_ROOT="$(launchlayer_root)"
	export SCRIPT REPO_ROOT
	export STEAM_ROOT="${STEAM_ROOT:-$HOME/.local/share/Steam}"
}

# bats_integration_teardown — Restore env vars some integration tests override.
bats_integration_teardown() {
	[[ -n "${BATS_SAVED_HOME:-}" ]] && export HOME="$BATS_SAVED_HOME"
	if [[ -n "${BATS_SAVED_XDG_CONFIG_HOME:-}" ]]; then
		export XDG_CONFIG_HOME="$BATS_SAVED_XDG_CONFIG_HOME"
	else
		unset XDG_CONFIG_HOME
	fi
	rm -rf "${BATS_TEST_STATE_HOME:-}"
	if [[ -n "${BATS_SAVED_XDG_STATE_HOME:-}" ]]; then
		export XDG_STATE_HOME="$BATS_SAVED_XDG_STATE_HOME"
	else
		unset XDG_STATE_HOME
	fi
	unset LAUNCHLAYER_HUB_FINGERPRINT_LEVEL
	stop_hub_mock_server
}

# engine_detect_reset — Clear tracked fake Steam roots between engine tests.
engine_detect_reset() {
	ENGINE_FAKE_STEAM_ROOTS=()
	ENGINE_FIXTURE_DIR=""
	ENGINE_FIXTURE_STEAM=""
}

# engine_detect_teardown — Remove fake Steam roots created during engine tests.
engine_detect_teardown() {
	local d
	for d in "${ENGINE_FAKE_STEAM_ROOTS[@]:-}"; do
		[[ -n "$d" ]] && rm -rf "$d"
	done
	engine_detect_reset
}

# engine_setup_fixture — Create a fake installed game; sets ENGINE_FIXTURE_DIR/STEAM.
engine_setup_fixture() {
	local appid=$1 name=$2
	local installdir=${3:-Game${appid}}
	local fake
	fake="$(fake_steam_root "$appid" "$name" "$installdir")"
	ENGINE_FAKE_STEAM_ROOTS+=("$fake")
	# shellcheck disable=SC2034  # fixture paths read by test/unit/engine-detect.bats
	ENGINE_FIXTURE_STEAM="$fake"
	# shellcheck disable=SC2034  # fixture paths read by test/unit/engine-detect.bats
	ENGINE_FIXTURE_DIR="$fake/steamapps/common/$installdir"
}

# engine_run_detect — Run detect_engine_hint for an AppID (sets bats run status/output).
engine_run_detect() {
	local appid=$1 fake_steam=$2
	local helpers_dir="${BATS_TEST_DIRNAME:-}"
	[[ -n "$helpers_dir" ]] || helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unit"
	run env STEAM_ROOT="$fake_steam" CONFIG_DIR="${CONFIG_DIR:-$(launchlayer_root)}" bash -c '
		source "'"${helpers_dir}"'/../helpers.bash"
		source_lib steam config
		detect_engine_hint '"$appid"'
	'
}

# engine_assert_hint — Assert the last detect_engine_hint result matches expected engine id.
engine_assert_hint() {
	local expected=$1
	[[ $status -eq 0 ]] || {
		echo "detect_engine_hint failed (status=$status): $output" >&2
		return 1
	}
	[[ "$output" == "$expected" ]] || {
		echo "expected engine=$expected got=$output" >&2
		return 1
	}
}

# engine_run_markers — Run _detect_engine_markers on a directory path directly.
engine_run_markers() {
	local game_dir=$1
	local helpers_dir="${BATS_TEST_DIRNAME:-}"
	[[ -n "$helpers_dir" ]] || helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unit"
	run env CONFIG_DIR="${CONFIG_DIR:-$(launchlayer_root)}" bash -c '
		source "'"${helpers_dir}"'/../helpers.bash"
		source_lib steam config
		_detect_engine_markers "'"$game_dir"'"
	'
}

# engine_run_collect_roots — Run _engine_collect_scan_roots for assertions on scan coverage.
engine_run_collect_roots() {
	local game_dir=$1
	local helpers_dir="${BATS_TEST_DIRNAME:-}"
	[[ -n "$helpers_dir" ]] || helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unit"
	run env CONFIG_DIR="${CONFIG_DIR:-$(launchlayer_root)}" bash -c '
		source "'"${helpers_dir}"'/../helpers.bash"
		source_lib steam config
		_engine_collect_scan_roots "'"$game_dir"'" | sort
	'
}

# source_lib — Source lib modules with CONFIG_DIR and LIB_DIR set.
# Pass modular tree names (platform, hardware, inspect, …) or single-file modules (cli, steam, …).
# LIB_DIR always points at the repo lib/ tree; CONFIG_DIR may be a temp dir for isolated tests.
source_lib() {
	local repo module
	repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	export CONFIG_DIR="${CONFIG_DIR:-$repo}"
	export LIB_DIR="$repo/lib"
	source "$LIB_DIR/common.sh"
	[[ -n "${LAUNCHLAYER_LOAD_MODULES_LOADED:-}" ]] || source "$LIB_DIR/load-modules.sh"
	for module in "$@"; do
		_source_lib_module "$repo" "$module"
	done
}

# tui_bats_menu_stub_install — Subshell-safe tui_menu queue (use with _tui_menu_queue array).
# Call tui_bats_menu_stub_teardown when the test shell exits.
tui_bats_menu_stub_install() {
	_tui_menu_idx_file="$(mktemp)"
	echo 0 > "$_tui_menu_idx_file"
	# shellcheck disable=SC2329
	tui_menu() {
		local idx choice
		idx="$(<"$_tui_menu_idx_file")"
		choice="${_tui_menu_queue[$idx]:-Back}"
		echo $((idx + 1)) > "$_tui_menu_idx_file"
		printf '%s\n' "$choice"
	}
	# shellcheck disable=SC2329
	tui_menu_anchored() {
		shift 2
		tui_menu "$@"
	}
}

tui_bats_menu_stub_teardown() {
	rm -f "${_tui_menu_idx_file:-}"
}
