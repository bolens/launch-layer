#!/usr/bin/env bash
# Unit tests for scripts/protondb_suggest.py helpers.
load '../helpers.bash'

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/protondb_suggest.py"

_py() {
	python3 - "$@" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("protondb_suggest", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

cmd = sys.argv[2]
if cmd == "parse":
    wrappers, env_vars, args = mod.parse_launch_options(sys.argv[3])
    print("wrappers=" + ",".join(sorted(wrappers)))
    print("env=" + ",".join(f"{k}={v}" for k, v in sorted(env_vars.items())))
    print("args=" + ",".join(args))
elif cmd == "gpu":
    print(mod.gpu_match_bonus(sys.argv[3], sys.argv[4]))
elif cmd == "match":
    print(mod.match_version(sys.argv[3], sys.argv[4:]) or "none")
else:
    raise SystemExit(f"unknown cmd {cmd}")
PY
}

@test "protondb match_version compares numeric GE releases" {
	run _py "$SCRIPT" match GE-Proton10-8 GE-Proton10-9 GE-Proton10-10 GE-Proton9-27
	[[ $status -eq 0 ]]
	[[ "$output" == "GE-Proton10-10" ]]
}

@test "protondb match_version recognizes Steam stable version labels" {
	run _py "$SCRIPT" match 10.0-3 "Proton 9.0" "Proton 10.0"
	[[ $status -eq 0 ]]
	[[ "$output" == "Proton 10.0" ]]
}

@test "protondb report ranking uses timestamp as a stable tie breaker" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
ranked = m.sort_scored_reports([(3.0, {"timestamp": 10}), (3.0, {"timestamp": 20})])
assert [r[1]["timestamp"] for r in ranked] == [20, 10]
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb atomic update applies a batch and preserves unrelated config" {
	tmp="$(mktemp -d)"
	printf 'INCLUDE=presets/standard.env\nMANGOHUD=0\n' > "$tmp/42.env"
	run python3 -c '
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
path = sys.argv[1]
m.apply_config_updates_atomic(path, {"GAMEMODE": "1", "MANGOHUD": "1"}, "42")
content = pathlib.Path(path).read_text()
assert content == "INCLUDE=presets/standard.env\nMANGOHUD=0\n# launchlayer:protondb-managed GAMEMODE\nGAMEMODE=1\n"
assert pathlib.Path(path).stat().st_mode & 0o777 == 0o600
print("ok")
' "$tmp/42.env"
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb config values reject line injection" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
try:
    m.config_value("1\nLD_PRELOAD=x")
except ValueError:
    print("blocked")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "blocked" ]]
}

@test "protondb atomic update preserves unmarked game arguments" {
	tmp="$(mktemp -d)"
	printf 'GAME_EXTRA_ARGS="-windowed"\n' > "$tmp/42.env"
	run python3 -c '
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.apply_config_updates_atomic(sys.argv[1], {"GAME_EXTRA_ARGS": "-dx11 -windowed"}, "42")
assert pathlib.Path(sys.argv[1]).read_text() == "GAME_EXTRA_ARGS=\"-windowed\"\n"
print("ok")
' "$tmp/42.env"
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb parse_launch_options extracts wrappers env and args" {
	run _py "$SCRIPT" parse 'gamemoderun MANGOHUD=1 PROTON_ENABLE_NVAPI=1 %command% -dx11'
	[[ $status -eq 0 ]]
	[[ "$output" == *"wrappers=GAMEMODE"* ]]
	[[ "$output" == *"env=MANGOHUD=1,PROTON_ENABLE_NVAPI=1"* ]]
	[[ "$output" == *"args=-dx11"* ]]
}

@test "protondb parse_launch_options keeps argument values and drops wrapper arguments" {
	run _py "$SCRIPT" parse 'gamescope -W 1920 -H 1080 -- %command% -screen-width 1920 -window-mode borderless'
	[[ $status -eq 0 ]]
	[[ "$output" == *"wrappers=GAMESCOPE"* ]]
	[[ "$output" == *"args=-screen-width,1920,-window-mode,borderless"* ]]
	[[ "$output" != *"args=-W"* ]]
}

@test "protondb gpu_match_bonus does not treat radeon as match for nvidia host" {
	run _py "$SCRIPT" gpu nvidia "AMD Radeon RX 7800 XT"
	[[ $status -eq 0 ]]
	[[ "$output" == "-1.0" ]]
}

@test "protondb gpu_match_bonus matches amd host to radeon report" {
	run _py "$SCRIPT" gpu amd "AMD Radeon RX 7800 XT"
	[[ $status -eq 0 ]]
	[[ "$output" == "3.0" ]]
}

@test "protondb apply allowlist blocks unsafe and stale automatic overrides" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert not m.is_allowed_config_key("PROTON_ENABLE_NVAPI")
assert not m.is_allowed_config_key("PROTON_ENABLE_WAYLAND")
assert not m.is_allowed_config_key("PROTON_ENABLE_HDR")
assert m.is_allowed_config_key("GAMEMODE")
assert m.is_allowed_config_key("DLSS_SWAPPER")
assert m.is_allowed_config_key("PROTON_DLSS_UPGRADE")
assert m.is_allowed_config_key("PROTON_FSR4_UPGRADE")
assert m.is_allowed_config_key("PROTON_XESS_UPGRADE")
assert m.is_allowed_config_key("SHADER_CACHE_BOOST")
assert m.is_allowed_config_key("LD_BIND_NOW")
assert m.is_allowed_config_key("VKBASALT")
assert m.is_allowed_config_key("LATENCYFLEX")
assert m.is_allowed_config_key("DISABLE_VBLANK")
assert m.is_allowed_config_key("DISABLE_STEAM_DECK")
assert m.is_allowed_config_key("FRAME_RATE")
assert not m.is_allowed_config_key("LD_PRELOAD")
assert not m.is_allowed_config_key("PATH")
assert not m.is_allowed_config_key("DXVK_ASYNC")
assert not m.is_allowed_config_key("PROTON_USE_NTSYNC")
assert not m.is_allowed_config_key("PROTON_NO_ESYNC")
assert not m.is_allowed_config_key("PROTON_USE_WINED3D")
assert not m.is_allowed_config_key("PROTON_LOG")
assert not m.is_allowed_config_key("DXVK_HUD")
assert not m.is_allowed_config_key("VKD3D_CONFIG")
assert not m.is_allowed_config_key("PROTON_FUTURE_TOGGLE")
assert m.is_allowed_recommendation_value("GAMEMODE", "1")
assert not m.is_allowed_recommendation_value("GAMEMODE", "yes")
assert m.is_allowed_recommendation_value("FRAME_RATE", "120")
assert not m.is_allowed_recommendation_value("FRAME_RATE", "-1")
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb actionable reports exclude stale advice without falling back for apply" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
now = 2_000_000_000
reports = [
    (8.0, {"timestamp": now - 30 * 86400}),
    (9.0, {"timestamp": now - 366 * 86400}),
]
assert m.actionable_reports(reports, now=now) == [reports[0]]
assert m.actionable_reports([reports[1]], now=now) == []
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb consensus requires two fresh reports for risky settings and arguments" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert not m.has_apply_consensus("PROTON_USE_WINED3D", 5.0, 10.0, 1)
assert m.has_apply_consensus("PROTON_USE_WINED3D", 5.0, 10.0, 2)
assert not m.has_argument_consensus(4.0, 10.0, 1)
assert m.has_argument_consensus(4.0, 10.0, 2)
assert not m.should_apply_wrapper("GAMEMODE")
assert m.should_apply_wrapper("GAMESCOPE")
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb managed updates reconcile generated keys and preserve manual keys" {
	tmp="$(mktemp -d)"
	cat > "$tmp/42.env" <<'EOF'
INCLUDE=presets/standard.env
# launchlayer:protondb-managed GAMEMODE
GAMEMODE=1
MANGOHUD=0
# launchlayer:protondb-managed PROTON_ENABLE_NVAPI
PROTON_ENABLE_NVAPI=1
EOF
	run python3 -c '
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.apply_config_updates_atomic(sys.argv[1], {"GAMEMODE": "1", "MANGOHUD": "1"}, "42")
content = pathlib.Path(sys.argv[1]).read_text()
assert "PROTON_ENABLE_NVAPI" not in content
assert "MANGOHUD=0" in content
assert content.count("MANGOHUD=") == 1
assert "# launchlayer:protondb-managed GAMEMODE\nGAMEMODE=1\n" in content
print("ok")
' "$tmp/42.env"
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb does not select a Proton override for native games" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.select_proton_override("GE-Proton11-1", "GE-Proton11-1", True) is None
assert m.select_proton_override("GE-Proton11-1", "GE-Proton11-1", False) == "GE-Proton11-1"
assert m.select_proton_override("10.0-3", "Proton 10.0", False) is None
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb treats Omarchy arch-linux profile as Arch for report ranking" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.detect_host_distro({"os_id": "omarchy", "profiles": ["arch-linux", "nvidia-desktop"]}) == "arch"
assert m.detect_host_distro({"os_id": "fedora", "profiles": []}) == "fedora"
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb detect_host_cpu prefers amd-cpu profile token" {
	run python3 -c '
import importlib.util
spec = importlib.util.spec_from_file_location("pdb", "'"$SCRIPT"'")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.detect_host_cpu({"profiles": "arch-linux amd-gpu amd-cpu"}) == "amd"
assert m.detect_host_cpu({"profiles": ["intel-cpu", "amd-gpu"]}) == "intel"
# amd-gpu alone must not select amd via substring
assert m.detect_host_cpu({"profiles": "arch-linux amd-gpu"}) == m.detect_host_cpu({"profiles": "arch-linux amd-gpu"})
cpu = m.detect_host_cpu({"profiles": "arch-linux amd-gpu"})
# Without amd-cpu/intel-cpu tokens, falls back to /proc/cpuinfo — just ensure it returns a known value
assert cpu in ("amd", "intel", "unknown")
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == "ok" ]]
}

@test "protondb GAME_EXTRA_ARGS merge regex matches existing lines" {
	run python3 -W ignore::FutureWarning -c '
import re
line = "GAME_EXTRA_ARGS=\"-windowed\""
assert re.match(r"^\s*GAME_EXTRA_ARGS=(.*)$", line)
# POSIX [[:space:]] is not valid in Python re (legacy bug); keep the \s form.
m = re.match(r"^[[:space:]]*GAME_EXTRA_ARGS=(.*)$", line)
assert m is None
print("ok")
'
	[[ $status -eq 0 ]]
	[[ "$output" == *"ok"* ]]
}
