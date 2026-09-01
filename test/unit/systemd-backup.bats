#!/usr/bin/env bash
# Unit tests for backup systemd timer helpers.
load '../helpers.bash'

setup() {
	bats_unit_setup
}

@test "systemd_exec_quote escapes systemd expansion and quoting characters" {
	source_lib setup prefs
	run systemd_exec_quote '/games/Launch $Layer/%build/it"s/launchlayer'
	[[ $status -eq 0 ]]
	[[ "$output" == '"/games/Launch $$Layer/%%build/it\"s/launchlayer"' ]]
}

@test "generated systemd services use direct ExecStart commands" {
	local tmp
	tmp="$(mktemp -d)"
	run env HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup prefs
		LAUNCHLAYER_MAIN_SCRIPT="/games/Launch Layer/launchlayer"
		systemctl() { return 1; }
		export -f systemctl
		install_systemd_user_units
		LAUNCHLAYER_BACKUP_DIR="'"$tmp"'/backups"
		backup_prefs_apply_env() { :; }
		install_systemd_backup_units 0
	'
	[[ $status -eq 0 ]]
	grep -Fq 'ExecStart="/games/Launch Layer/launchlayer" --run-maintenance' "$tmp/config/systemd/user/launchlayer-maintenance.service"
	grep -Fq 'ExecStart="/games/Launch Layer/launchlayer" --run-scheduled-backup' "$tmp/config/systemd/user/launchlayer-backup.service"
	! grep -q '/bin/bash -c' "$tmp/config/systemd/user/launchlayer-maintenance.service"
	! grep -q '/bin/bash -c' "$tmp/config/systemd/user/launchlayer-backup.service"
	rm -rf "$tmp"
}

@test "systemd_backup_timer_brief_state reports not_installed" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		tmp="$(mktemp -d)"
		export XDG_CONFIG_HOME="$tmp" HOME="$tmp"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		systemd_backup_timer_brief_state
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "not_installed" ]]
}

@test "systemd_backup_units_installed_p is false without unit files" {
	run bash -c '
		export CONFIG_DIR="'"$CONFIG_DIR"'"
		tmp="$(mktemp -d)"
		export XDG_CONFIG_HOME="$tmp" HOME="$tmp"
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib setup
		systemd_backup_units_installed_p && echo yes || echo no
	'
	[[ $status -eq 0 ]]
	[[ "$output" == "no" ]]
}
