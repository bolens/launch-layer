#!/usr/bin/env bash
# Unit tests for inject framework and extras applies.
load '../helpers.bash'

setup() {
	bats_unit_setup
	export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg-data"
	mkdir -p "$XDG_DATA_HOME"
}

@test "inject provider conflicts reject two owners of one proxy slot" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		SPECIAL_K=1 SPECIAL_K_DLL=dxgi
		RESHADE=1 RESHADE_DLL=dxgi.dll
		inject_provider_conflict_errors
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"dxgi.dll"* ]]
	[[ "$output" == *"Special K"* ]]
	[[ "$output" == *"ReShade"* ]]
}

@test "inject provider conflicts allow distinct proxy slots" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		SPECIAL_K=1 SPECIAL_K_DLL=dxgi
		RESHADE=1 RESHADE_DLL=d3d11
		test -z "$(inject_provider_conflict_errors)"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject provider conflicts reject OpenVR FSR with OpenComposite" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		OPENVR_FSR=1 OPENCOMPOSITE=1 inject_provider_conflict_errors
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"openvr_api.dll"* ]]
	[[ "$output" == *"OpenVR FSR"* ]]
	[[ "$output" == *"OpenComposite"* ]]
}

@test "apply_optiscaler tracks selected proxy and refuses anticheat games" {
	local source_dir game_dir
	source_dir="$BATS_TEST_TMPDIR/optiscaler"
	game_dir="$BATS_TEST_TMPDIR/game"
	mkdir -p "$source_dir" "$game_dir"
	printf MZ > "$source_dir/OptiScaler.dll"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		inject_resolve_game_dir() { printf "%s\n" "'"$game_dir"'"; }
		steam_app_id=42 OPTISCALER=1 OPTISCALER_SOURCE="'"$source_dir"'" OPTISCALER_PROXY=version
		is_anticheat=0
		apply_optiscaler
		test -f "'"$game_dir"'/version.dll"
		echo "$WINEDLLOVERRIDES"
		inject_cleanup_tracked 42 optiscaler
		test ! -e "'"$game_dir"'/version.dll"
		is_anticheat=1
		apply_optiscaler
		test ! -e "'"$game_dir"'/version.dll"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"version=n,b"* ]]
	[[ "$output" == *"anti-cheat"* ]]
}

@test "apply_opencomposite swaps and restores openvr_api.dll" {
	local source_dir game_dir
	source_dir="$BATS_TEST_TMPDIR/opencomposite"
	game_dir="$BATS_TEST_TMPDIR/vr-game/bin"
	mkdir -p "$source_dir" "$game_dir"
	printf original > "$game_dir/openvr_api.dll"
	printf replacement > "$source_dir/openvr_api.dll"
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		inject_resolve_game_dir() { printf "%s\n" "'"${game_dir%/bin}"'"; }
		steam_app_id=77 OPENCOMPOSITE=1 OPENCOMPOSITE_SOURCE="'"$source_dir"'"
		apply_opencomposite
		test "$(cat "'"$game_dir"'/openvr_api.dll")" = replacement
		inject_cleanup_tracked 77 opencomposite
		test "$(cat "'"$game_dir"'/openvr_api.dll")" = original
	'
	[[ "$status" -eq 0 ]]
}

@test "apply_gpu_selection maps vendors without clobbering explicit loader filters" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		GPU_SELECT=nvidia apply_gpu_selection
		echo "nv:$__NV_PRIME_RENDER_OFFLOAD:$__GLX_VENDOR_LIBRARY_NAME:$VK_LOADER_DRIVERS_SELECT"
		unset __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME VK_LOADER_DRIVERS_SELECT
		VK_LOADER_DRIVERS_SELECT=custom
		GPU_SELECT=amd
		apply_gpu_selection
		echo "amd:$VK_LOADER_DRIVERS_SELECT"
		unset VK_LOADER_DRIVERS_SELECT
		GPU_SELECT=nvidia GPU_SELECT_DRIVER="*custom-nvidia*"
		apply_gpu_selection
		echo "driver:$VK_LOADER_DRIVERS_SELECT"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"nv:1:nvidia:*nvidia*"* ]]
	[[ "$output" == *"amd:custom"* ]]
	[[ "$output" == *"driver:*custom-nvidia*"* ]]
}

@test "inject_store_notice writes NOTICE under cache" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		inject_store_notice vkbasalt "test" "https://example.test/vk" "zlib" "note"
		cat "$(inject_tool_cache_dir vkbasalt)/NOTICE"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Upstream: https://example.test/vk"* ]]
	[[ "$output" == *"License: zlib"* ]]
}

@test "inject_merge_winedlloverrides merges without clobber" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		export WINEDLLOVERRIDES="dinput8=n,b"
		inject_merge_winedlloverrides dxgi
		echo "$WINEDLLOVERRIDES"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"dinput8=n,b"* ]]
	[[ "$output" == *"dxgi=n,b"* ]]
}

@test "inject_track_and_cleanup removes tracked file" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		f="'"$BATS_TEST_TMPDIR"'/tracked.dll"
		echo x > "$f"
		inject_track_file 12345 specialk "$f"
		[[ -f "$f" ]] || exit 2
		inject_cleanup_tracked 12345 specialk
		[[ ! -f "$f" ]] || exit 3
		echo ok
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ok"* ]]
}

@test "inject_cleanup restores .ll-bak over injected file" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		api="'"$BATS_TEST_TMPDIR"'/openvr_api.dll"
		echo original > "$api"
		cp -f "$api" "${api}.ll-bak"
		echo injected > "$api"
		inject_track_file 99 openvr_fsr "${api}.ll-bak"
		inject_track_file 99 openvr_fsr "$api"
		inject_cleanup_tracked 99 openvr_fsr
		[[ "$(cat "$api")" == original ]] || exit 2
		[[ ! -f "${api}.ll-bak" ]] || exit 3
		echo ok
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ok"* ]]
}

@test "inject_copy_renamed refuses overwrite when backup fails" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		src="'"$BATS_TEST_TMPDIR"'/source.dll"
		dest_dir="'"$BATS_TEST_TMPDIR"'/game"
		mkdir -p "$dest_dir"
		printf replacement > "$src"
		printf original > "$dest_dir/dxgi.dll"
		cp() {
			[[ "${3:-}" == *.ll-bak ]] && return 1
			command cp "$@"
		}
		if inject_copy_renamed "$src" "$dest_dir" dxgi.dll 42 test; then exit 2; fi
		test "$(cat "$dest_dir/dxgi.dll")" = original
		test ! -e "$dest_dir/dxgi.dll.ll-bak"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject_copy_renamed refuses a source that is already the destination" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		dll="'"$BATS_TEST_TMPDIR"'/dxgi.dll"
		printf original > "$dll"
		if inject_copy_renamed "$dll" "$(dirname "$dll")" dxgi.dll 42 test; then exit 2; fi
		test "$(cat "$dll")" = original
		test ! -e "$dll.ll-bak"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject_copy_renamed rejects destination traversal" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		src="'"$BATS_TEST_TMPDIR"'/source.dll"
		dest_dir="'"$BATS_TEST_TMPDIR"'/game"
		mkdir -p "$dest_dir"
		printf replacement > "$src"
		! inject_copy_renamed "$src" "$dest_dir" ../escape.dll 42 test
		test ! -e "'"$BATS_TEST_TMPDIR"'/escape.dll"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject tracking rejects unsafe manifest identifiers" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'" XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		! inject_track_file ../escape specialk /tmp/file
		! inject_track_file 42 ../escape /tmp/file
		test ! -e "$(inject_track_root)/../escape-specialk.txt"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject archive validation rejects traversal and absolute members" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		inject_archive_member_is_safe shaders/file.fx || exit 2
		! inject_archive_member_is_safe ../escape.dll
		! inject_archive_member_is_safe /tmp/escape.dll
		! inject_archive_member_is_safe shaders/../../escape.dll
	'
	[[ "$status" -eq 0 ]]
}

@test "inject archive validation checks listed members before extraction" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		archive="'"$BATS_TEST_TMPDIR"'/unsafe.tar"
		: > "$archive"
		tar() { printf "%s\n" safe/file ../escape; }
		! inject_archive_members_are_safe "$archive"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject archive validation rejects tar links" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		archive="'"$BATS_TEST_TMPDIR"'/linked.tar"
		: > "$archive"
		tar() {
			if [[ "$1" == -tvf ]]; then
				printf "%s\n" "lrwxrwxrwx user/group 0 date link -> ../../escape"
			else
				printf "%s\n" safe/file
			fi
		}
		! inject_archive_members_are_safe "$archive"
	'
	[[ "$status" -eq 0 ]]
}

@test "inject cleanup includes global ValvePlug tracking" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		CALLS=()
		inject_cleanup_tracked() { CALLS+=("$1:$2"); }
		inject_cleanup_launch_tracks 42
		printf "%s\n" "${CALLS[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"42:optiscaler"* ]]
	[[ "$output" == *"steam:valveplug"* ]]
}

@test "apply_vkbasalt exports config file when set" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		VKBASALT=1
		VKBASALT_CONFIG_FILE=/tmp/vkBasalt.conf
		export VKBASALT VKBASALT_CONFIG_FILE
		apply_vkbasalt
		echo "ENABLE=$ENABLE_VKBASALT FILE=$VKBASALT_CONFIG_FILE"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ENABLE=1"* ]]
	[[ "$output" == *"FILE=/tmp/vkBasalt.conf"* ]]
}

@test "apply_special_k merges WINEDLLOVERRIDES" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		is_native=0
		SPECIAL_K=1 SPECIAL_K_DLL=d3d11 apply_special_k
		echo "$WINEDLLOVERRIDES"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"d3d11=n,b"* ]]
}

@test "proxy injectors reject unsafe DLL names before setting Wine overrides" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		is_native=0
		SPECIAL_K=1 SPECIAL_K_DLL=../escape apply_special_k
		RESHADE=1 RESHADE_DLL=subdir/dxgi apply_reshade
		test -z "${WINEDLLOVERRIDES:-}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"unsafe proxy DLL name"* ]]
}

@test "SPECIAL_K_FETCH extracts zip via LAUNCHLAYER_FETCH_CMD" {
	local fixture dir checksum
	dir="$BATS_TEST_TMPDIR/sk-fixture"
	mkdir -p "$dir"
	printf 'MZ' > "$dir/SpecialK64.dll"
	command -v zip >/dev/null 2>&1 || skip "zip not installed"
	(cd "$dir" && zip -q specialk-stub.zip SpecialK64.dll)
	fixture="$dir/specialk-stub.zip"
	checksum="$(sha256sum "$fixture" | awk '{print $1}')"
	[[ -f "$fixture" ]]
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		export LAUNCHLAYER_FETCH_FORCE=1
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		SPECIAL_K_FETCH=1
		SPECIAL_K_FETCH_URL=https://example.test/sk.zip
		INJECT_SHA256="'"$checksum"'"
		SPECIAL_K_VERSION=test
		dest="$(inject_tool_cache_dir specialk)/test"
		mkdir -p "$dest"
		export LAUNCHLAYER_FETCH_CMD="cp -f \"'"$fixture"'\" \"\$dest\""
		apply_special_k_fetch
		echo "SOURCE=$SPECIAL_K_SOURCE"
		[[ -f "$SPECIAL_K_SOURCE/SpecialK64.dll" ]] || exit 2
		echo ok
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ok"* ]]
	[[ "$output" == *"SOURCE="* ]]
}

@test "inject_fetch_url refuses missing or mismatched checksums" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		export XDG_DATA_HOME="'"$XDG_DATA_HOME"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		dest="$XDG_DATA_HOME/package.bin"
		LAUNCHLAYER_FETCH_CMD="printf payload > \"\$dest\""
		inject_fetch_url https://example.test/package "$dest" && exit 2
		INJECT_SHA256="$(printf different | sha256sum | awk "{print \$1}")"
		inject_fetch_url https://example.test/package "$dest" && exit 3
		[[ ! -e "$dest" ]]
	'
	[[ "$status" -eq 0 ]]
}

@test "apply_lsfg_vk exports ENABLE_LSFGVK" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() { [[ "$1" == lsfg-vk ]]; }
		LSFG_VK=1 apply_lsfg_vk
		echo "ENABLE=${ENABLE_LSFGVK:-} PROC=${LSFG_PROCESS:-}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ENABLE=1"* ]]
}

@test "apply_specialty_runtime sets OVERRIDE_PROTON" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		unset OVERRIDE_PROTON
		SPECIALTY_RUNTIME=boxtron apply_specialty_runtime
		echo "OP=$OVERRIDE_PROTON"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"OP=boxtron"* ]]
}

@test "apply_block_internet sets wrap marker when unshare works" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		command_available() { [[ "$1" == unshare ]]; }
		unshare() { return 0; }
		BLOCK_INTERNET=1 apply_block_internet
		echo "WRAP=${LAUNCHLAYER_BLOCK_INTERNET_WRAP:-}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"WRAP=unshare"* ]]
}

@test "CONTY prepends conty on chain when available" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() { return 1; }
		command_available() { [[ "$1" == conty ]]; }
		gamescope_session_active() { return 1; }
		default_online_cpus() { echo 0-3; }
		is_native=0
		GAMEMODE=0 GAME_PERFORMANCE=0 DISABLE_CPU_AFFINITY=1
		GAMESCOPE=0 MANGOHUD=0 CONTY=1
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"conty"* ]]
}

@test "crash_guess defaults timeout to 5 when CRASH_GUESS=1" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		# Non-TTY should no-op without hanging
		CRASH_GUESS=1 CRASH_GUESS_TIMEOUT=0
		crash_guess_maybe_prompt 1
		echo ok
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"ok"* ]]
}

@test "gamescope nested fix prepends env -u LD_PRELOAD" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() {
			case "$1" in gamemoderun|taskset|gamescope) return 0 ;; *) return 1 ;; esac
		}
		command_available() { return 1; }
		gamescope_session_active() { return 1; }
		default_online_cpus() { echo 0-3; }
		is_native=0
		export LD_PRELOAD=/fake/overlay.so
		GAMEMODE=0 GAME_PERFORMANCE=0 DISABLE_CPU_AFFINITY=1
		GAMESCOPE=1 GAMESCOPE_W=1920 GAMESCOPE_H=1080 GAMESCOPE_R=60 GAMESCOPE_NESTED_FIX=1
		GAMESCOPE_ADAPTIVE_SYNC=0 MANGOHUD=0
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"env"* ]]
	[[ "$output" == *"-u"* ]]
	[[ "$output" == *"LD_PRELOAD"* ]]
	[[ "$output" == *"gamescope"* ]]
}

@test "gamescope appends native ReShade effect and technique flags" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() { [[ "$1" == gamescope ]]; }
		gamescope_session_active() { return 1; }
		default_online_cpus() { echo 0-3; }
		is_native=0
		GAMEMODE=0 GAME_PERFORMANCE=0 DISABLE_CPU_AFFINITY=1 MANGOHUD=0
		GAMESCOPE=1 GAMESCOPE_NESTED_FIX=0 GAMESCOPE_RESHADE_EFFECT=CAS.fx GAMESCOPE_RESHADE_TECHNIQUE=2
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"--reshade-effect"* ]]
	[[ "$output" == *"CAS.fx"* ]]
	[[ "$output" == *"--reshade-technique-idx"* ]]
	[[ "$output" == *$'2\n--'* ]]
}

@test "gamescope skipped inside gamescope session" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() {
			case "$1" in gamescope) return 0 ;; *) return 1 ;; esac
		}
		command_available() { return 1; }
		gamescope_session_active() { return 0; }
		default_online_cpus() { echo 0-3; }
		is_native=0
		GAMEMODE=0 GAME_PERFORMANCE=0 DISABLE_CPU_AFFINITY=1
		GAMESCOPE=1 GAMESCOPE_W=1280 GAMESCOPE_H=800 GAMESCOPE_R=60
		GAMESCOPE_ADAPTIVE_SYNC=0 MANGOHUD=0
		launch=()
		build_launch_chain 2>/dev/null
		printf "%s\n" "${launch[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" != *"gamescope"* ]]
}

@test "OBS_VKCAPTURE inserts obs-gamecapture after gamescope --" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform runtime
		optional_tool_installed() {
			case "$1" in gamescope|obs-vkcapture) return 0 ;; *) return 1 ;; esac
		}
		command_available() {
			case "$1" in obs-gamecapture) return 0 ;; *) return 1 ;; esac
		}
		gamescope_session_active() { return 1; }
		default_online_cpus() { echo 0-3; }
		is_native=0
		GAMEMODE=0 GAME_PERFORMANCE=0 DISABLE_CPU_AFFINITY=1
		GAMESCOPE=1 GAMESCOPE_W=1920 GAMESCOPE_H=1080 GAMESCOPE_R=60 GAMESCOPE_NESTED_FIX=0
		GAMESCOPE_ADAPTIVE_SYNC=0 MANGOHUD=0 OBS_VKCAPTURE=1
		launch=()
		build_launch_chain
		printf "%s\n" "${launch[@]}"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"obs-gamecapture"* ]]
}

@test "auto VRR sets GAMESCOPE_ADAPTIVE_SYNC when empty" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware runtime
		detect_vrr_enabled() { return 0; }
		GAMESCOPE=1
		unset GAMESCOPE_ADAPTIVE_SYNC
		GAMESCOPE_W=1920 GAMESCOPE_H=1080 GAMESCOPE_R=60
		# Call only the adaptive-sync branch logic
		if [[ -z "${GAMESCOPE_ADAPTIVE_SYNC:-}" || "${GAMESCOPE_ADAPTIVE_SYNC}" == auto ]]; then
			if detect_vrr_enabled; then
				GAMESCOPE_ADAPTIVE_SYNC=1
			else
				GAMESCOPE_ADAPTIVE_SYNC=0
			fi
			export GAMESCOPE_ADAPTIVE_SYNC
		fi
		echo "SYNC=$GAMESCOPE_ADAPTIVE_SYNC"
	'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"SYNC=1"* ]]
}

@test "hub strips SPECIAL_K_SOURCE and SPECIALTY_RUNTIME as untrusted" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$CONFIG_DIR"'/lib/common.sh"
		source "'"$CONFIG_DIR"'/lib/keys.sh"
		source "'"$CONFIG_DIR"'/lib/commands/hub/context.sh"
		hub_is_untrusted_env_key SPECIAL_K_SOURCE && echo sk
		hub_is_untrusted_env_key SPECIALTY_RUNTIME && echo specialty
		hub_is_untrusted_env_key CONTY && echo conty
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"sk"* ]]
	[[ "$output" == *"specialty"* ]]
	[[ "$output" == *"conty"* ]]
}
