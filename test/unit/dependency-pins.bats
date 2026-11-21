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

@test "dependency pin check accepts aliases pinned to exact npm versions" {
	cat > "$PIN_ROOT/hub/package.json" <<'JSON'
{
  "packageManager": "pnpm@10.16.1",
  "devDependencies": {
    "typescript-native": "npm:typescript@7.0.2",
    "scoped-alias": "npm:@scope/package@1.2.3-beta.1"
  }
}
JSON

	run bash -c 'cd "$1" && bash "$2"' _ \
		"$PIN_ROOT" "$CONFIG_DIR/scripts/check-dependency-pins.sh"

	[[ $status -eq 0 ]]
}

@test "dependency pin check rejects npm aliases with ranges and tags" {
	cat > "$PIN_ROOT/hub/package.json" <<'JSON'
{
  "packageManager": "pnpm@10.16.1",
  "dependencies": {
    "range-alias": "npm:typescript@^7.0.0",
    "tag-alias": "npm:@scope/package@latest"
  }
}
JSON

	run bash -c 'cd "$1" && bash "$2"' _ \
		"$PIN_ROOT" "$CONFIG_DIR/scripts/check-dependency-pins.sh"

	[[ $status -ne 0 ]]
	[[ "$output" == *"dependencies.range-alias must use an exact version"* ]]
	[[ "$output" == *"dependencies.tag-alias must use an exact version"* ]]
}
