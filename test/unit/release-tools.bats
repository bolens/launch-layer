#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "bump-version performs a portable atomic rewrite" {
	local tmp fake_bin original_mode
	tmp="$(mktemp -d)"
	fake_bin="$tmp/bin"
	mkdir -p "$tmp/repo/scripts" "$tmp/repo/lib" "$fake_bin"
	cp "$REPO_ROOT/scripts/bump-version.sh" "$tmp/repo/scripts/"
	printf '%s\n' '#!/usr/bin/env bash' 'LAUNCHLAYER_VERSION=1.2.3' > "$tmp/repo/lib/cli.sh"
	chmod 751 "$tmp/repo/lib/cli.sh"
	original_mode="$(stat -c %a "$tmp/repo/lib/cli.sh" 2>/dev/null || stat -f %Lp "$tmp/repo/lib/cli.sh")"
	cat > "$fake_bin/sed" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" != -i* ]] || exit 91
exec /usr/bin/sed "$@"
EOF
	chmod +x "$fake_bin/sed"

	run env PATH="$fake_bin:$PATH" bash "$tmp/repo/scripts/bump-version.sh" 1.2.4
	[[ $status -eq 0 ]]
	[[ "$(sed -n 's/^LAUNCHLAYER_VERSION=//p' "$tmp/repo/lib/cli.sh")" == 1.2.4 ]]
	[[ "$(stat -c %a "$tmp/repo/lib/cli.sh" 2>/dev/null || stat -f %Lp "$tmp/repo/lib/cli.sh")" == "$original_mode" ]]
	[[ ! -e "$tmp/repo/lib/.cli-version."* ]]
	rm -rf "$tmp"
}
