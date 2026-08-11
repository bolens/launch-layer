#!/usr/bin/env bats
load '../helpers.bash'

setup() {
	bats_unit_setup
	PIN_ROOT="$(mktemp -d)"
	mkdir -p "$PIN_ROOT/.github/workflows" "$PIN_ROOT/hub"
	cat > "$PIN_ROOT/hub/package.json" <<'EOF'
{
  "packageManager": "pnpm@10.16.1",
  "dependencies": { "example": "1.2.3" }
}
EOF
	cat > "$PIN_ROOT/hub/pnpm-lock.yaml" <<'EOF'
packages:
  example@1.2.3:
    resolution: {integrity: sha512-dGVzdA==}
EOF
	cat > "$PIN_ROOT/hub/pnpm-workspace.yaml" <<'EOF'
overrides:
  example: 1.2.3
EOF
}

teardown() {
	rm -rf "$PIN_ROOT"
}

@test "dependency pin check rejects reusable job tags in yaml workflows" {
	cat > "$PIN_ROOT/.github/workflows/reusable.yaml" <<'EOF'
jobs:
  external:
    uses: owner/repo/.github/workflows/check.yml@v1
EOF

	run bash -c 'cd "$1" && bash "$2"' _ \
		"$PIN_ROOT" "$CONFIG_DIR/scripts/check-dependency-pins.sh"

	[[ $status -ne 0 ]]
	[[ "$output" == *"full commit SHA"* ]]
}

@test "dependency pin check accepts SHA actions and local reusable jobs" {
	cat > "$PIN_ROOT/.github/workflows/checks.yml" <<'EOF'
jobs:
  local:
    uses: ./.github/workflows/local.yml
  test:
    steps:
      - uses: owner/action@0123456789abcdef0123456789abcdef01234567
EOF

	run bash -c 'cd "$1" && bash "$2"' _ \
		"$PIN_ROOT" "$CONFIG_DIR/scripts/check-dependency-pins.sh"

	[[ $status -eq 0 ]]
}
