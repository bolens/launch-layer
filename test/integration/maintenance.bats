#!/usr/bin/env bash
# Integration tests for doctor, status, scans, and maintenance commands.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "doctor runs" {
	run "$SCRIPT" --doctor
	[[ $status -eq 0 ]]
	[[ "$output" == *"launchlayer doctor"* ]]
}

@test "doctor json runs" {
	run "$SCRIPT" --doctor --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"issue_count"'* ]]
	[[ "$output" == *'"config_validation_issues"'* ]]
	python3 -c 'import json,sys; json.loads(sys.argv[1])' "$output"
}

@test "doctor json includes optional tools" {
	run "$SCRIPT" --doctor --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"optional_tools"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "optional_tools" in d' "$output"
}

@test "doctor includes config validation section" {
	run "$SCRIPT" --doctor
	[[ $status -eq 0 ]]
	[[ "$output" == *"Config validation"* ]]
}

@test "doctor json includes issues array" {
	run "$SCRIPT" --doctor --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"issues"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert isinstance(d["issues"], list)' "$output"
}

@test "status text runs" {
	run "$SCRIPT" --status
	[[ $status -eq 0 ]]
	[[ "$output" == *"launchlayer status"* ]]
}

@test "launch-stats json with no filter" {
	run "$SCRIPT" --launch-stats --json
	[[ $status -eq 0 ]]
	[[ "$output" == *'"entries"'* ]]
	python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert "entries" in d and isinstance(d["entries"], list)' "$output"
}

@test "scan-anticheat runs with fake steam library" {
	local fake_steam
	fake_steam="$(fake_steam_root 42424242 "Test Game")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --scan-anticheat
	[[ $status -eq 0 ]]
	[[ "$output" == *"Anticheat scan"* ]]
	[[ "$output" == *"APPID"* ]]
	rm -rf "$fake_steam"
}

@test "scan-detections runs with fake steam library" {
	local fake_steam
	fake_steam="$(fake_steam_root 42424242 "Test Game")"
	run env STEAM_ROOT="$fake_steam" "$SCRIPT" --scan-detections
	[[ $status -eq 0 ]]
	[[ "$output" == *"Detection audit"* ]]
	rm -rf "$fake_steam"
}

@test "install-systemd writes user units in temp home" {
	local tmp unit_dir
	tmp="$(mktemp -d)"
	unit_dir="$tmp/.config/systemd/user"
	run env HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" "$SCRIPT" --install-systemd
	[[ $status -eq 0 ]]
	[[ "$output" == *"systemd"* || "$output" == *"launchlayer-maintenance"* || "$output" == *"timer"* ]]
	[[ -f "$unit_dir/launchlayer-maintenance.service" ]]
	[[ -f "$unit_dir/launchlayer-maintenance.timer" ]]
	grep -q launchlayer "$unit_dir/launchlayer-maintenance.service"
	grep -q -- '--run-maintenance' "$unit_dir/launchlayer-maintenance.service"
	! grep -q '/bin/bash -c' "$unit_dir/launchlayer-maintenance.service"
	rm -rf "$tmp"
}

@test "sysctl status runs" {
	run "$SCRIPT" --sysctl status
	[[ $status -eq 0 ]]
	[[ "$output" == *"vm.max_map_count"* ]]
}

@test "show-cpu-topology runs" {
	run "$SCRIPT" --show-cpu-topology
	[[ $status -eq 0 ]]
	[[ "$output" == *"CPU topology"* || "$output" == *"lscpu"* || "$output" == *"X3D"* ]]
}

@test "no args prints brief usage" {
	run "$SCRIPT"
	[[ $status -eq 0 ]]
	[[ "$output" == *"--help"* ]]
	[[ "$output" == *"--doctor"* ]]
}

@test "help mentions launch-stats and sysctl" {
	run "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ "$output" == *"--launch-stats"* ]]
	[[ "$output" == *"--sysctl"* ]]
	[[ "$output" == *"--show-cpu-topology"* ]]
}
