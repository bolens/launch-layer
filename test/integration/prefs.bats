#!/usr/bin/env bash
# Integration tests for backup pruning and preference templates.
load '../helpers.bash'

setup() {
	bats_integration_setup
}

teardown() {
	bats_integration_teardown
}

@test "prune-backups dry-run keeps newest archives" {
	local tmp backup_dir i
	tmp="$(mktemp -d)"
	backup_dir="$tmp/backups"
	mkdir -p "$backup_dir"
	for i in 1 2 3; do
		echo "backup$i" > "$backup_dir/launchlayer-backup-2026010${i}-12000${i}.tar.gz"
		sleep 0.01
	done
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" "$SCRIPT" --prune-backups --dir "$backup_dir" --keep 1 --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"would remove"* ]]
	[[ $(find "$backup_dir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 3 ]]
	rm -rf "$tmp"
}

@test "prune-backups removes oldest archives" {
	local tmp backup_dir i
	tmp="$(mktemp -d)"
	backup_dir="$tmp/backups"
	mkdir -p "$backup_dir"
	for i in 1 2 3; do
		echo "backup$i" > "$backup_dir/launchlayer-backup-2026010${i}-12000${i}.tar.gz"
		sleep 0.01
	done
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" "$SCRIPT" --prune-backups --dir "$backup_dir" --keep 1
	[[ $status -eq 0 ]]
	[[ "$output" == *"removed=2"* ]]
	[[ $(find "$backup_dir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 1 ]]
	rm -rf "$tmp"
}

@test "prune-backups keep=0 retains all archives" {
	local tmp backup_dir i
	tmp="$(mktemp -d)"
	backup_dir="$tmp/backups"
	mkdir -p "$backup_dir"
	for i in 1 2 3; do
		echo "backup$i" > "$backup_dir/launchlayer-backup-2026010${i}-12000${i}.tar.gz"
	done
	run env LAUNCHLAYER_CONFIG_DIR="$tmp" "$SCRIPT" --prune-backups --dir "$backup_dir" --keep 0
	[[ $status -eq 0 ]]
	[[ "$output" == *"unlimited retention"* ]]
	[[ $(find "$backup_dir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 3 ]]
	rm -rf "$tmp"
}

@test "prune-backups uses backup.conf dir and keep when flags omitted" {
	local tmp backup_dir i
	tmp="$(mktemp -d)"
	backup_dir="$tmp/conf-backups"
	mkdir -p "$backup_dir" "$tmp/launchlayer"
	for i in 1 2 3; do
		echo "backup$i" > "$backup_dir/launchlayer-backup-2026010${i}-12000${i}.tar.gz"
		sleep 0.01
	done
	cat > "$tmp/launchlayer/backup.conf" <<EOF
backup_dir=$backup_dir
keep=1
timer_type=calendar
on_calendar=*-*-* 03:15:00
on_boot_sec=15min
on_unit_active_sec=12h
randomized_delay_sec=1800
include_local=1
include_profiles=1
include_tui=0
auto_prune=1
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --prune-backups --dry-run
	[[ $status -eq 0 ]]
	[[ "$output" == *"$backup_dir"* ]]
	[[ "$output" == *"keep=1"* || "$output" == *'"keep":1'* ]]
	[[ "$output" == *"would remove"* ]]
	[[ $(find "$backup_dir" -maxdepth 1 -name 'launchlayer-backup-*.tar.gz' | wc -l) -eq 3 ]]
	rm -rf "$tmp"
}

@test "tui-prefs reset restores repo defaults" {
	local tmp example
	tmp="$(mktemp -d)"
	example="$tmp/share/launchlayer/templates/tui.conf.example"
	mkdir -p "$(dirname "$example")"
	cat > "$example" <<'EOF'
game_filter=configured
cache_min_gb=10
default_preset=competitive
fzf_height=50%
fzf_preview=down:40%:wrap
EOF
	mkdir -p "$tmp/launchlayer"
	cat > "$tmp/launchlayer/tui.conf" <<'EOF'
game_filter=all
cache_min_gb=1
default_preset=lightweight
fzf_height=20%
fzf_preview=left:30%:wrap
EOF
	run env \
		LAUNCHLAYER_CONFIG_DIR="$tmp" \
		XDG_CONFIG_HOME="$tmp" \
		HOME="$tmp" \
		"$SCRIPT" --tui-prefs reset
	[[ $status -eq 0 ]]
	[[ "$output" == *"Reset TUI preferences"* ]]
	grep -q 'game_filter=configured' "$tmp/launchlayer/tui.conf"
	grep -q 'default_preset=competitive' "$tmp/launchlayer/tui.conf"
	rm -rf "$tmp"
}

@test "backup.conf.example contains all backup preference keys" {
	local example="$REPO_ROOT/share/launchlayer/templates/backup.conf.example"
	[[ -f "$example" ]]
	run bash -c '
		example="'"$example"'"
		for key in backup_dir keep timer_type on_calendar on_boot_sec on_unit_active_sec \
			randomized_delay_sec include_local include_profiles include_tui auto_prune; do
			grep -q "^${key}=" "$example" || { echo "missing:$key"; exit 1; }
			echo "present:$key"
		done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"present:backup_dir"* ]]
	[[ "$output" == *"present:auto_prune"* ]]
}

@test "tui.conf.example contains all TUI preference keys" {
	local example="$REPO_ROOT/share/launchlayer/templates/tui.conf.example"
	[[ -f "$example" ]]
	run bash -c '
		example="'"$example"'"
		for key in game_filter cache_min_gb default_preset last_menu json_output \
			resume_last_menu text_status spinner press_enter_lines fzf_height fzf_preview; do
			grep -q "^${key}=" "$example" || { echo "missing:$key"; exit 1; }
			echo "present:$key"
		done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"present:game_filter"* ]]
	[[ "$output" == *"present:fzf_preview"* ]]
}

@test "hub.conf.example contains hub preference keys" {
	local example="$REPO_ROOT/share/launchlayer/templates/hub.conf.example"
	[[ -f "$example" ]]
	run bash -c '
		example="'"$example"'"
		for key in hub_url publish_token machine_label fingerprint_level; do
			grep -q "^# ${key}=" "$example" || grep -q "^${key}=" "$example" || { echo "missing:$key"; exit 1; }
			echo "present:$key"
		done
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"present:hub_url"* ]]
	[[ "$output" == *"present:fingerprint_level"* ]]
}
