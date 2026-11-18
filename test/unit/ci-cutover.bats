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
native_shell = (root / '.woodpecker/shell.yml').read_text()
native_hub = (root / '.woodpecker/hub.yml').read_text()
native_repository = (root / '.woodpecker/repository.yml').read_text()

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

caller_shell = block(ci, 'shell', 2)
for key in ('full_linux_validation', 'minimum_runtime_validation'):
    contract = block(shell, key, 6)
    assert re.search(r'^        type: boolean$', contract, re.M)
    assert re.search(r'^        default: true$', contract, re.M)
    assert f'{key}: false' in caller_shell
for job in ('shellcheck', 'bats'):
    assert 'if: inputs.full_linux_validation' in block(shell, job, 2)
for job in ('mcp-python-minimum', 'bash-minimum'):
    assert 'if: inputs.minimum_runtime_validation' in block(shell, job, 2)
assert 'inputs.' not in block(shell, 'portability', 2)
assert 'os: [ubuntu-latest, macos-latest]' in shell
assert 'sudo sysctl' not in shell

combined = block(hub, 'combined_minimum', 6)
assert re.search(r'^        type: boolean$', combined, re.M)
assert re.search(r'^        default: false$', combined, re.M)
assert not re.search(r'^  (hub|supply_chain):$', ci, re.M)
legacy = block(hub, 'hub', 2)
assert 'if: ${{ !inputs.combined_minimum }}' in legacy
assert 'task: [lint, test, test:coverage]' in legacy
minimum = block(hub, 'minimum', 2)
assert 'if: inputs.combined_minimum' in minimum
assert 'node-version-file: .node-version' in minimum
assert 'install --frozen-lockfile' in minimum
for task in ('lint', 'test', 'test:coverage'):
    assert re.search(r'^          bash scripts/hub-pm.sh ' + re.escape(task) + '$', minimum, re.M)
minimum_node = (root / '.node-version').read_text().strip()
assert f'node:{minimum_node}-bookworm-slim@sha256:' in native_hub
assert '$(cat .node-version)' in native_hub
assert '- name: minimum-node' in native_hub
assert native_hub.count('bash scripts/woodpecker-linux.sh hub') == 2
assert '- name: minimum-python' in native_shell
assert 'python:3.9-slim-bookworm@sha256:' in native_shell
assert 'bats test/unit/mcp.bats' in native_shell
assert '- name: minimum-bash' in native_shell
assert 'bash scripts/ci/check-minimum-bash.sh' in native_shell
assert 'depth: 0' in native_repository
assert 'bash scripts/ci/check-history-secrets.sh' in native_repository
# The retained aggregate still rejects failed hosted checks and keeps the Pages artifact.
aggregate = block(ci, 'ci', 2)
assert 'needs: [changes, actionlint, pages, shell, editor]' in aggregate
assert 'shell suite required but result was' in aggregate
assert 'Pages artifact job did not succeed' in aggregate
PY
	if [[ $status -ne 0 ]]; then
		printf '%s\n' "$output" >&2
		return 1
	fi
}
