#!/usr/bin/env bats

@test "Bats shards partition both native suites without omissions or overlap" {
	run python3 - "$BATS_TEST_DIRNAME/../.." <<'PY'
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
for suite in ('unit', 'integration'):
    expected = sorted(str(path.relative_to(root)) for path in (root / 'test' / suite).glob('*.bats'))
    for count in (1, 2, 3):
        selected = []
        for index in range(count):
            result = subprocess.run(['bash', str(root / 'scripts/run-bats-shard.sh'), suite,
                                     str(index), str(count), 'python3', '-c',
                                     'import json,sys; print(json.dumps(sys.argv[1:]))'],
                                    check=True, capture_output=True, text=True)
            selected.extend(json.loads(result.stdout))
        assert sorted(selected) == expected, (suite, count)
        assert len(selected) == len(set(selected)), (suite, count)
PY
	[[ $status -eq 0 ]]
}

@test "Bats shard runner rejects invalid and empty partitions" {
	for arguments in 'unit 0 0' 'unit 2 2' 'unit -1 2' 'unit 0 x' 'unknown 0 1' 'integration 98 99'; do
		read -r -a parts <<<"$arguments"
		run bash "$BATS_TEST_DIRNAME/../../scripts/run-bats-shard.sh" "${parts[@]}" true
		[[ $status -eq 2 ]]
	done
}
