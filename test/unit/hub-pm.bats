#!/usr/bin/env bats
# Unit tests for scripts/hub-pm.sh (vp preferred, pnpm fallback).
load '../helpers.bash'

HUB_PM="$BATS_TEST_DIRNAME/../../scripts/hub-pm.sh"

setup() {
	bats_unit_setup
	FAKE_BIN="$(mktemp -d)"
	# Isolated PATH: stubs + bash/env/dirname so real /usr/bin/pnpm cannot leak in.
	ln -s "$(command -v bash)" "$FAKE_BIN/bash"
	ln -s "$(command -v env)" "$FAKE_BIN/env"
	ln -s "$(command -v dirname)" "$FAKE_BIN/dirname"
	TEST_PATH="$FAKE_BIN"
}

teardown() {
	rm -rf "${FAKE_BIN:-}"
}

# Write an executable stub that echoes its name and args, then exits 0.
_stub_echo() {
	local name=$1
	cat >"$FAKE_BIN/$name" <<EOF
#!/bin/bash
printf '%s' "$name"
[[ \$# -gt 0 ]] && printf ' %s' "\$@"
printf '\n'
EOF
	chmod +x "$FAKE_BIN/$name"
}

@test "hub-pm.sh usage exits 2 with no args" {
	run "$HUB_PM"
	[[ $status -eq 2 ]]
	[[ "$output" == *"usage:"* ]]
}

@test "hub-pm.sh fails when neither vp nor pnpm is available" {
	# No-op corepack so enable cannot install a real pnpm shim into PATH.
	cat >"$FAKE_BIN/corepack" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$FAKE_BIN/corepack"
	run env PATH="$TEST_PATH" "$HUB_PM" lint
	[[ $status -eq 1 ]]
	[[ "$output" == *"need vp"* ]]
}

@test "hub-pm.sh pnpm fallback forwards install args" {
	_stub_echo pnpm
	run env PATH="$TEST_PATH" "$HUB_PM" install --frozen-lockfile
	[[ $status -eq 0 ]]
	[[ "$output" == "pnpm install --frozen-lockfile" ]]
}

@test "hub-pm.sh does not replace an existing pnpm with Corepack" {
	_stub_echo pnpm
	cat >"$FAKE_BIN/corepack" <<'EOF'
#!/bin/bash
echo "corepack should not run" >&2
exit 1
EOF
	chmod +x "$FAKE_BIN/corepack"
	run env PATH="$TEST_PATH" "$HUB_PM" install --frozen-lockfile
	[[ $status -eq 0 ]]
	[[ "$output" == "pnpm install --frozen-lockfile" ]]
}

@test "hub-pm.sh pnpm fallback maps lint to pnpm run lint" {
	_stub_echo pnpm
	run env PATH="$TEST_PATH" "$HUB_PM" lint
	[[ $status -eq 0 ]]
	[[ "$output" == "pnpm run lint" ]]
}

@test "hub-pm.sh pnpm fallback maps run to pnpm run" {
	_stub_echo pnpm
	run env PATH="$TEST_PATH" "$HUB_PM" run test
	[[ $status -eq 0 ]]
	[[ "$output" == "pnpm run test" ]]
}

@test "hub-pm.sh prefers vp over pnpm when both are available" {
	_stub_echo vp
	_stub_echo pnpm
	run env PATH="$TEST_PATH" "$HUB_PM" run lint
	[[ $status -eq 0 ]]
	[[ "$output" == "vp run lint" ]]
}

@test "hub-pm.sh vp path maps lint to vp run lint" {
	_stub_echo vp
	run env PATH="$TEST_PATH" "$HUB_PM" lint
	[[ $status -eq 0 ]]
	[[ "$output" == "vp run lint" ]]
}

@test "hub-pm.sh vp path maps audit to vp pm audit" {
	_stub_echo vp
	run env PATH="$TEST_PATH" "$HUB_PM" audit
	[[ $status -eq 0 ]]
	[[ "$output" == "vp pm audit" ]]
}
