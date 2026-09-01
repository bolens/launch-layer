#!/usr/bin/env bash
# Integration tests for hardware and compositor detection helpers.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "detect_desktop_session recognizes additional compositors" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" HYPRLAND_INSTANCE_SIGNATURE= NIRI_SOCKET= RIVER_STATUS= LABWC_PID= WAYFIRE_CONFIG= COSMIC_SESSION= COSMIC_COMPOSITOR= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_CURRENT_DESKTOP=niri XDG_SESSION_DESKTOP= detect_desktop_session
	'
	[[ $status -eq 0 ]]
	[[ "$output" == niri ]]

	run env CONFIG_DIR="$root" HYPRLAND_INSTANCE_SIGNATURE= NIRI_SOCKET= RIVER_STATUS= LABWC_PID= WAYFIRE_CONFIG= COSMIC_SESSION= COSMIC_COMPOSITOR= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_CURRENT_DESKTOP=COSMIC XDG_SESSION_DESKTOP=KDE detect_desktop_session
	'
	[[ $status -eq 0 ]]
	[[ "$output" == cosmic ]]

	run env CONFIG_DIR="$root" HYPRLAND_INSTANCE_SIGNATURE= NIRI_SOCKET= RIVER_STATUS= LABWC_PID= WAYFIRE_CONFIG= COSMIC_SESSION= COSMIC_COMPOSITOR= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_CURRENT_DESKTOP= XDG_SESSION_DESKTOP=XFCE detect_desktop_session
	'
	[[ $status -eq 0 ]]
	[[ "$output" == xfce ]]

	run env CONFIG_DIR="$root" HYPRLAND_INSTANCE_SIGNATURE= NIRI_SOCKET= RIVER_STATUS= LABWC_PID= WAYFIRE_CONFIG= COSMIC_SESSION= COSMIC_COMPOSITOR= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_CURRENT_DESKTOP=Budgie XDG_SESSION_DESKTOP= detect_desktop_session
	'
	[[ $status -eq 0 ]]
	[[ "$output" == budgie ]]

	run env CONFIG_DIR="$root" HYPRLAND_INSTANCE_SIGNATURE= NIRI_SOCKET= RIVER_STATUS= LABWC_PID= WAYFIRE_CONFIG= COSMIC_SESSION= COSMIC_COMPOSITOR= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_CURRENT_DESKTOP= XDG_SESSION_DESKTOP=i3 detect_desktop_session
	'
	[[ $status -eq 0 ]]
	[[ "$output" == i3 ]]
}

@test "compositor_session_active does not match without socket" {
	local root="$REPO_ROOT"
	local fake_bin
	fake_bin="$(mktemp -d)"
	cat > "$fake_bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || exit 1
exit 0
EOF
	chmod +x "$fake_bin/hyprctl"
	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		unset HYPRLAND_INSTANCE_SIGNATURE
		XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-1
		compositor_session_active hyprland && echo active || echo inactive
	'
	[[ $status -eq 0 ]]
	[[ "$output" == inactive ]]
	rm -rf "$fake_bin"
}

@test "is_immutable_os detects bazzite id" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		read_os_release_field() {
			case "$1" in
				ID) echo bazzite ;;
				VARIANT_ID|IMAGE_ID) echo "" ;;
			esac
		}
		is_immutable_os && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == yes ]]
}

@test "detect_gpus_json lists discrete and integrated GPUs" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		_gpu_role_guess amd "Advanced Micro Devices, Inc. [AMD/ATI] Raphael"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == integrated ]]

	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform cli
		detect_gpus_json
	'
	[[ $status -eq 0 ]]
	[[ "$output" == \[* ]]
}

@test "detect_kwin_display_mode parses kscreen-doctor multi-monitor output" {
	local root="$REPO_ROOT"
	local fake_bin
	fake_bin="$(mktemp -d)"
	cat > "$fake_bin/kscreen-doctor" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Output: 1 HDMI-A-1 uuid-a
	priority 3
	Modes:  1:1920x1080@60.00*!
	Geometry: 0,667 1920x1080
Output: 2 DP-1 uuid-b
	priority 1
	Modes:  27:3440x1440@120.00*!
	Geometry: 1920,0 3440x1440
Output: 3 DP-3 uuid-c
	priority 2
	Modes:  34:2560x1440@164.85*!
	Geometry: 5360,150 2560x1440
OUT
EOF
	chmod +x "$fake_bin/kscreen-doctor"
	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		detect_kwin_primary_output
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "DP-1" ]]

	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		detect_kwin_display_mode
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "3440 1440 120 DP-1" ]]

	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware cli
		detect_displays_json
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"DP-1"* ]]
	[[ "$output" == *'"primary":true'* || "$output" == *'"primary": true'* ]]
	rm -rf "$fake_bin"
}

@test "detect_xrandr_display_mode parses xrandr output" {
	local root="$REPO_ROOT"
	local fake_bin
	fake_bin="$(mktemp -d)"
	cat > "$fake_bin/xrandr" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
DP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 527mm x 296mm
   1920x1080     60.00*+  144.00
OUT
EOF
	chmod +x "$fake_bin/xrandr"
	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		detect_xrandr_display_mode
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "1920 1080 60 DP-1" ]]
	rm -rf "$fake_bin"
}

@test "is_wayland_session detects Wayland env" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		XDG_SESSION_TYPE=wayland is_wayland_session && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == yes ]]

	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		unset XDG_SESSION_TYPE WAYLAND_DISPLAY
		is_wayland_session && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == no ]]
}

@test "parse_json_focused_monitor extracts hyprland monitor" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		printf "%s\n" "[{\"name\":\"DP-1\",\"width\":3440,\"height\":1440,\"refreshRate\":144.0,\"focused\":true}]" \
			| parse_json_focused_monitor
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "3440 1440 144 DP-1" ]]
}

@test "parse_json_focused_vrr detects adaptive sync" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		printf "%s\n" "[{\"name\":\"DP-1\",\"focused\":true,\"vrr\":true}]" \
			| parse_json_focused_vrr && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == yes ]]
}

@test "detect_river_display_mode parses riverctl text" {
	local root="$REPO_ROOT"
	local fake_bin
	fake_bin="$(mktemp -d)"
	cat > "$fake_bin/riverctl" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
Monitor: DP-2
	Status: connected
	Mode: 2560x1440@165.00Hz
	Focused: yes
OUT
EOF
	chmod +x "$fake_bin/riverctl"
	run env CONFIG_DIR="$root" PATH="$fake_bin:$PATH" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform hardware
		detect_river_display_mode
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "2560 1440 165 DP-2" ]]
	rm -rf "$fake_bin"
}

@test "detect_os_family maps distro IDs" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		read_os_release_field() {
			case "$1" in
				ID) echo ubuntu ;;
				ID_LIKE) echo debian ;;
				PRETTY_NAME) echo "Ubuntu 24.04" ;;
			esac
		}
		detect_os_family
	'
	[[ $status -eq 0 ]]
	[[ "$output" == debian ]]

	run env CONFIG_DIR="$root" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		read_os_release_field() {
			case "$1" in
				ID) echo fedora ;;
				ID_LIKE) echo "" ;;
			esac
		}
		detect_os_profile
	'
	[[ $status -eq 0 ]]
	[[ "$output" == fedora ]]
}

@test "detect_default_profiles includes distro profile" {
	local root="$REPO_ROOT"
	run env CONFIG_DIR="$root" LAUNCHLAYER_PROFILES= bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib platform
		detect_default_profiles
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"nvidia-desktop"* || "$output" == *"amd-gpu"* || "$output" == *"intel-gpu"* || "$output" == *"arch-linux"* || "$output" == *"debian"* ]]
}
