#!/usr/bin/env bash
# Unit tests for lib/keys.sh.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "known_config_key accepts INCLUDE and core keys" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		known_config_key INCLUDE && known_config_key GAMEMODE && known_config_key MANGOHUD
		echo all-known
	'
	[[ $status -eq 0 ]]
	[[ "$output" == all-known ]]
}

@test "known_config_key and summary registry include DLSS_SWAPPER" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		known_config_key DLSS_SWAPPER || { echo missing-known; exit 1; }
		printf "%s\n" "${LAUNCHLAYER_SUMMARY_KEYS[@]}" | grep -qx DLSS_SWAPPER || {
			echo missing-summary
			exit 1
		}
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "known_config_key and summary registry include upscaler and shader-boost keys" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		for key in SHADER_CACHE_BOOST SHADER_CACHE_BOOST_GB \
			PROTON_DLSS_UPGRADE PROTON_DLSS_INDICATOR \
			PROTON_FSR4_UPGRADE PROTON_FSR4_RDNA3_UPGRADE PROTON_FSR4_INDICATOR \
			PROTON_XESS_UPGRADE PROTON_NVIDIA_LIBS PROTON_NVIDIA_LIBS_NO_32BIT; do
			known_config_key "$key" || { echo "missing-known:$key"; exit 1; }
		done
		for key in SHADER_CACHE_BOOST PROTON_DLSS_UPGRADE PROTON_FSR4_UPGRADE PROTON_XESS_UPGRADE; do
			printf "%s\n" "${LAUNCHLAYER_SUMMARY_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-summary:$key"
				exit 1
			}
		done
		printf "%s\n" "${LAUNCHLAYER_CONFIG_KEYS[@]}" | grep -qx SHADER_CACHE_BOOST_GB || {
			echo missing-config-gb
			exit 1
		}
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "known_config_key and summary registry include Bazzite Deck/FPS keys" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		for key in DISABLE_STEAM_DECK FRAME_RATE; do
			known_config_key "$key" || { echo "missing-known:$key"; exit 1; }
			printf "%s\n" "${LAUNCHLAYER_SUMMARY_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-summary:$key"
				exit 1
			}
			printf "%s\n" "${LAUNCHLAYER_CONFIG_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-config:$key"
				exit 1
			}
		done
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "known_config_key and summary registry include Arch latency keys" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		for key in LD_BIND_NOW VKBASALT LATENCYFLEX DISABLE_VBLANK; do
			known_config_key "$key" || { echo "missing-known:$key"; exit 1; }
			printf "%s\n" "${LAUNCHLAYER_SUMMARY_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-summary:$key"
				exit 1
			}
			printf "%s\n" "${LAUNCHLAYER_CONFIG_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-config:$key"
				exit 1
			}
		done
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "known_config_key includes extended first-party tools" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		for key in LSFG_VK OBS_VKCAPTURE SPECIAL_K RESHADE GAMESCOPE_EXTRA_ARGS \
			WINETRICKS_VERBS CONTY BLOCK_INTERNET OPENVR_FSR PLAYTIME_LOG VKBASALT_CONFIG_FILE; do
			known_config_key "$key" || { echo "missing:$key"; exit 1; }
			printf "%s\n" "${LAUNCHLAYER_CONFIG_KEYS[@]}" | grep -qx "$key" || {
				echo "missing-config:$key"
				exit 1
			}
		done
		echo ok
	'
	[[ $status -eq 0 ]]
	[[ "$output" == ok ]]
}

@test "known_config_key accepts proton and wine prefixes" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		known_config_key PROTON_USE_WINED3D && known_config_key WINEPREFIX && known_config_key __GL_SYNC_TO_VBLANK
		echo all-known
	'
	[[ $status -eq 0 ]]
	[[ "$output" == all-known ]]
}

@test "known_config_key rejects unknown keys" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		known_config_key TOTALLY_FAKE_KEY && echo known || echo unknown
	'
	[[ $status -eq 0 ]]
	[[ "$output" == unknown ]]
}

@test "config key metadata exposes type TUI summary and Hub policy" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		printf "%s|%s|%s\n" \
			"$(config_key_kind GAMEMODE)" \
			"$(config_key_tui_surface GAMEMODE)" \
			"$(config_key_hub_policy PRE_LAUNCH_CMD)"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "boolean|toggle|untrusted" ]]
}

@test "config key metadata Hub policy matches shipped untrusted list" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib keys
		metadata="$(mktemp)"
		list="$(mktemp)"
		for key in "${!LAUNCHLAYER_CONFIG_KEY_HUB[@]}"; do
			[[ "${LAUNCHLAYER_CONFIG_KEY_HUB[$key]}" == untrusted ]] && printf "%s\n" "$key"
		done | sort > "$metadata"
		sed "/^[[:space:]]*#/d;/^[[:space:]]*$/d" "$(launchlayer_share_dir)/hub-untrusted-keys.txt" | sort > "$list"
		diff -u "$list" "$metadata"
		rm -f "$metadata" "$list"
	'
	[[ $status -eq 0 ]]
}
