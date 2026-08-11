#!/usr/bin/env bash
# Enforce immutable GitHub Action refs and exact, integrity-checked npm deps.
set -euo pipefail

status=0

workflow_uses_lines() {
	if command -v rg >/dev/null 2>&1; then
		rg -n --glob '*.yml' --glob '*.yaml' \
			'^[[:space:]]*(-[[:space:]]*)?uses:' .github/workflows
	else
		grep -R -n -E --include='*.yml' --include='*.yaml' \
			'^[[:space:]]*(-[[:space:]]*)?uses:' .github/workflows || true
	fi
}

while IFS=: read -r file line content; do
	ref="${content##*@}"
	ref="${ref%%[[:space:]#]*}"
	[[ "$content" == *"uses: ./"* ]] && continue
	if [[ ! "$ref" =~ ^[a-f0-9]{40}$ ]]; then
		printf '%s:%s: GitHub Action must use a full commit SHA: %s\n' \
			"$file" "$line" "$content" >&2
		status=1
	fi
done < <(
	workflow_uses_lines
)

python3 - <<'PY' || status=1
import json
import pathlib
import re
import sys

package_path = pathlib.Path("hub/package.json")
package = json.loads(package_path.read_text())
failed = False
for section in ("dependencies", "devDependencies", "optionalDependencies"):
    for name, version in package.get(section, {}).items():
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
            print(f"{package_path}: {section}.{name} must use an exact version, got {version!r}", file=sys.stderr)
            failed = True

manager = package.get("packageManager", "")
if not re.fullmatch(r"pnpm@\d+\.\d+\.\d+", manager):
    print(f"{package_path}: packageManager must pin an exact pnpm version", file=sys.stderr)
    failed = True

lock_path = pathlib.Path("hub/pnpm-lock.yaml")
lock = lock_path.read_text()
resolutions = [line for line in lock.splitlines() if "resolution:" in line]
missing = [line for line in resolutions if "integrity: sha512-" not in line]
if not resolutions or missing:
    print(f"{lock_path}: every package resolution must carry a sha512 integrity hash", file=sys.stderr)
    failed = True

workspace_path = pathlib.Path("hub/pnpm-workspace.yaml")
workspace = workspace_path.read_text()
in_overrides = False
for line in workspace.splitlines():
    if line == "overrides:":
        in_overrides = True
        continue
    if in_overrides and line and not line.startswith(" "):
        break
    if in_overrides and re.match(r"^  [^#][^:]*:", line):
        name, version = line.strip().split(":", 1)
        version = version.strip().strip("'\"")
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
            print(f"{workspace_path}: override {name} must use an exact version, got {version!r}", file=sys.stderr)
            failed = True

raise SystemExit(1 if failed else 0)
PY

exit "$status"
