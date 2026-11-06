#!/usr/bin/env bats

@test "ordinary CI opts into native Linux while reusable defaults preserve coverage" {
	run python3 - "$BATS_TEST_DIRNAME/../.." <<'PY'
from pathlib import Path
import re
import sys
root = Path(sys.argv[1]).resolve()
ci = (root / '.github/workflows/ci.yml').read_text()
shell = (root / '.github/workflows/ci-shell.yml').read_text()
hub = (root / '.github/workflows/ci-hub.yml').read_text()

def block(text, key, indent):
    lines = text.splitlines()
    start = lines.index(' ' * indent + key + ':')
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        end += 1
    return '\n'.join(lines[start:end])

full = block(shell, 'full_linux_validation', 6)
assert re.search(r'^        type: boolean$', full, re.M)
assert re.search(r'^        default: true$', full, re.M)
assert 'full_linux_validation: false' in block(ci, 'shell', 2)
for job in ('shellcheck', 'bats'):
    assert 'if: inputs.full_linux_validation' in block(shell, job, 2)
for job in ('mcp-python-minimum', 'bash-minimum', 'portability'):
    assert 'inputs.full_linux_validation' not in block(shell, job, 2)
assert 'os: [ubuntu-latest, macos-latest]' in shell
assert 'sudo sysctl' not in shell

combined = block(hub, 'combined_minimum', 6)
assert re.search(r'^        type: boolean$', combined, re.M)
assert re.search(r'^        default: false$', combined, re.M)
assert 'combined_minimum: true' in block(ci, 'hub', 2)
legacy = block(hub, 'hub', 2)
assert 'if: ${{ !inputs.combined_minimum }}' in legacy
assert 'task: [lint, test, test:coverage]' in legacy
minimum = block(hub, 'minimum', 2)
assert 'if: inputs.combined_minimum' in minimum
assert 'node-version-file: .node-version' in minimum
assert 'install --frozen-lockfile' in minimum
for task in ('lint', 'test', 'test:coverage'):
    assert re.search(r'^          bash scripts/hub-pm.sh ' + re.escape(task) + '$', minimum, re.M)
assert (root / '.node-version').read_text().strip() == '22.13.0'
# Existing selected-suite aggregation must still reject actual failures.
assert 'shell_result' in block(ci, 'ci', 2) and 'hub_result' in block(ci, 'ci', 2)
assert 'shell suite required but result was' in ci
assert 'hub suite required but result was' in ci
PY
	[[ $status -eq 0 ]]
}
