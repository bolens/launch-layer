#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
import re
import os
import shlex
import time
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from collections import defaultdict

try:
    import fcntl
except ImportError:
    fcntl = None

# ANSI Colors
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
CYAN = "\033[36m"
WHITE = "\033[37m"
RESET = "\033[0m"

# Map tier to rating color
TIER_COLORS = {
    "platinum": CYAN,
    "gold": YELLOW,
    "silver": WHITE,
    "bronze": RED,
    "borked": RED,
    "pending": DIM
}

def get_hash(app_id, reports, timestamp, page="all"):
    def R(e, t, n):
        try:
            t_num = float(t)
        except ValueError:
            t_num = float('nan')
        try:
            e_num = float(e)
        except ValueError:
            e_num = float('nan')
        try:
            n_num = float(n)
        except ValueError:
            n_num = float('nan')
            
        import math
        if math.isnan(e_num) or math.isnan(t_num) or math.isnan(n_num):
            val = float('nan')
        else:
            val = e_num * (t_num % n_num)
            
        if math.isnan(val):
            val_str = "NaN"
        else:
            if val == int(val):
                val_str = str(int(val))
            else:
                val_str = str(val)
        return f"{t}p{val_str}"

    def I(s):
        s_m = s + "m"
        h = 0
        for char in s_m:
            code = ord(char)
            h = ((h << 5) - h + code) & 0xFFFFFFFF
            if h >= 0x80000000:
                h -= 0x100000000
        return abs(h)

    part1 = R(app_id, reports, timestamp)
    part2 = R(page, app_id, timestamp)
    final_str = f"p{part1}*vRT{part2}undefined"
    return I(final_str)

def list_installed_proton_tools(steam_root=None):
    roots = []
    if steam_root:
        roots.append(steam_root)
    home = os.path.expanduser("~")
    roots.extend([
        os.path.join(home, ".local/share/Steam"),
        os.path.join(home, ".steam/root"),
        os.path.join(home, ".steam/steam"),
        os.path.join(home, ".var/app/com.valvesoftware.Steam/data/Steam")
    ])
    
    installed = set()
    for root in roots:
        ct_dir = os.path.join(root, "compatibilitytools.d")
        if os.path.isdir(ct_dir):
            for d in os.listdir(ct_dir):
                if os.path.isfile(os.path.join(ct_dir, d, "proton")):
                    installed.add(d)
        common_dir = os.path.join(root, "steamapps", "common")
        if os.path.isdir(common_dir):
            for d in os.listdir(common_dir):
                if os.path.isfile(os.path.join(common_dir, d, "proton")):
                    installed.add(d)
    return sorted(installed, key=version_sort_key)


def version_sort_key(value):
    """Compare embedded version numbers numerically and text case-insensitively."""
    return tuple(int(part) if part.isdigit() else part.lower()
                 for part in re.split(r'(\d+)', value))

def gpu_match_bonus(host_gpu, rep_gpu):
    """Score bump when report GPU matches host GPU vendor."""
    if host_gpu == "unknown" or not rep_gpu:
        return 0.0
    host = host_gpu.lower()
    rep = rep_gpu.lower()
    if host in rep:
        return 3.0
    if host == "nvidia" and "nvidia" in rep:
        return 3.0
    if host == "amd" and ("amd" in rep or "radeon" in rep):
        return 3.0
    if host == "intel" and "intel" in rep:
        return 3.0
    return -1.0


# Deliberately narrower than LaunchLayer's config registry. Community reports may
# only automate named, bounded settings; unknown Proton/DXVK/VKD3D keys stay text.
_AUTO_APPLY_CONFIG_KEYS = {
    "GAMEMODE", "MANGOHUD", "GAMESCOPE", "DLSS_SWAPPER",
    "PROTON_DLSS_UPGRADE", "PROTON_FSR4_UPGRADE", "PROTON_XESS_UPGRADE",
    "SHADER_CACHE_BOOST", "LD_BIND_NOW",
    "VKBASALT", "LATENCYFLEX", "DISABLE_VBLANK", "DISABLE_STEAM_DECK",
    "FRAME_RATE",
}
_COMPATIBILITY_CONFIG_KEYS = {
    "PROTON_USE_WINED3D", "PROTON_NO_FSYNC", "PROTON_NO_ESYNC",
    "PROTON_NO_D3D11", "PROTON_NO_D3D10", "PROTON_HIDE_NVIDIA_GPU",
}
_BLOCKED_APPLY_KEYS = {
    "LD_PRELOAD", "LD_LIBRARY_PATH", "PATH", "HOME", "USER", "SHELL", "PWD", "OLDPWD",
    "SSH_AUTH_SOCK", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR",
}
_IGNORED_RECOMMENDATION_KEYS = {
    # Do not automate obsolete, fork-only, or long-removed performance toggles.
    "DXVK_ASYNC", "PROTON_USE_NTSYNC", "PROTON_NO_ESYNC",
}


def is_allowed_config_key(key: str) -> bool:
    return bool(key and key not in _BLOCKED_APPLY_KEYS
                and key not in _IGNORED_RECOMMENDATION_KEYS
                and key in _AUTO_APPLY_CONFIG_KEYS)


def is_compatibility_key(key: str) -> bool:
    return key in _COMPATIBILITY_CONFIG_KEYS and key not in _IGNORED_RECOMMENDATION_KEYS


def is_allowed_recommendation_value(key: str, value: str) -> bool:
    value = str(value)
    if key == "DLSS_SWAPPER":
        return value in {"0", "1", "dll"}
    if key == "FRAME_RATE":
        return value.isdigit() and 1 <= int(value) <= 1000
    if key in _AUTO_APPLY_CONFIG_KEYS or key in _COMPATIBILITY_CONFIG_KEYS:
        return value in {"0", "1"}
    return False


def actionable_reports(scored_reports, now=None, max_age_days=365):
    """Return reports recent enough to drive automatic config changes."""
    now = time.time() if now is None else now
    cutoff = now - max_age_days * 86400
    return [item for item in scored_reports
            if item[0] > 0 and item[1].get("timestamp", 0) >= cutoff]


def has_apply_consensus(key, vote_score, total_score, report_count):
    """Require corroboration, with a higher bar for compatibility fallbacks."""
    threshold = 0.35 if is_compatibility_key(key) else 0.15
    return report_count >= 2 and total_score > 0 and vote_score / total_score >= threshold


def has_argument_consensus(vote_score, total_score, report_count):
    return report_count >= 2 and total_score > 0 and vote_score / total_score >= 0.35


def should_apply_wrapper(wrapper):
    # GAMEMODE=1 is already the shipped default and should not become a
    # redundant per-game override.
    return wrapper in {"MANGOHUD", "GAMESCOPE"}


def select_proton_override(suggested, matched, game_native):
    if game_native or not suggested or not matched:
        return None
    # Steam keeps Valve's stable Proton current. Pin only a custom tool whose
    # behavior cannot be obtained from the default compatibility selection.
    if re.match(r'^Proton\s+\d', matched, re.IGNORECASE):
        return None
    return matched


def detect_host_distro(env_info: dict) -> str:
    profiles = env_info.get("profiles", "")
    if isinstance(profiles, list):
        tokens = [str(profile).lower() for profile in profiles]
    else:
        tokens = str(profiles).lower().replace(",", " ").split()
    if "arch-linux" in tokens:
        return "arch"
    return str(env_info.get("os_id", "unknown")).lower()


def detect_host_cpu(env_info: dict) -> str:
    profiles = env_info.get("profiles", "")
    if isinstance(profiles, list):
        tokens = [str(p).lower() for p in profiles]
    else:
        tokens = str(profiles).lower().replace(",", " ").split()
    if "amd-cpu" in tokens:
        return "amd"
    if "intel-cpu" in tokens:
        return "intel"
    if os.path.isfile("/proc/cpuinfo"):
        cpu_content = open("/proc/cpuinfo", encoding="utf-8", errors="ignore").read().lower()
        if "authenticamd" in cpu_content:
            return "amd"
        if "genuineintel" in cpu_content:
            return "intel"
    return "unknown"


HTTP_TIMEOUT_SEC = 15


def fetch_json(url: str):
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "LaunchLayer/1.0 (+https://github.com/bolens/launch-layer; protondb-suggest)"},
    )
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SEC) as resp:
        return json.loads(resp.read().decode("utf-8"))


def parse_launch_options(options_str):
    wrappers = {}
    env_vars = {}
    extra_args = []
    if not options_str:
        return wrappers, env_vars, extra_args
        
    try:
        tokens = shlex.split(options_str)
    except Exception:
        tokens = options_str.split()
        
    command_index = tokens.index("%command%") if "%command%" in tokens else len(tokens)
    prefix_tokens = tokens[:command_index]
    if command_index < len(tokens):
        extra_args = [token for token in tokens[command_index + 1:] if token]

    for token in prefix_tokens:
        token = token.strip()
        if not token:
            continue
        if token == "gamemoderun":
            wrappers["GAMEMODE"] = True
        elif token == "mangohud":
            wrappers["MANGOHUD"] = True
        elif token == "gamescope":
            wrappers["GAMESCOPE"] = True
        elif '=' in token and not token.startswith('-'):
            parts = token.split('=', 1)
            key, val = parts[0], parts[1]
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', key):
                val = val.strip('"\'')
                # Ignore generic paths or binaries like LD_PRELOAD=/usr/lib/libtcmalloc.so (though let's keep others)
                if not (key == "LD_PRELOAD" and "tcmalloc" in val):
                    env_vars[key] = val

    return wrappers, env_vars, extra_args

def match_version(suggested, installed):
    if not suggested:
        return None
    s_lower = suggested.lower()
    installed = sorted(installed, key=version_sort_key)
    
    # Check exact match
    for inst in installed:
        if inst.lower() == s_lower:
            return inst
            
    # Check GE-Proton patterns
    if "ge" in s_lower or "proton-ge" in s_lower:
        # e.g., suggested = "GE-Proton10-34" or "GE-Proton9-22"
        # Extract major and minor if possible
        match = re.search(r'ge-proton(\d+)(?:-(\d+))?', s_lower)
        if match:
            major = match.group(1)
            minor = match.group(2) if match.group(2) else ""
            # Find closest installed GE-Proton
            ge_installed = [inst for inst in installed if "ge-proton" in inst.lower()]
            if ge_installed:
                # prefer same major
                matching_major = [inst for inst in ge_installed if f"ge-proton{major}" in inst.lower()]
                if matching_major:
                    return matching_major[-1] # return latest minor of same major
                return ge_installed[-1] # return latest GE version
        else:
            ge_installed = [inst for inst in installed if "ge-proton" in inst.lower()]
            if ge_installed:
                return ge_installed[-1]
                
    # Experimental
    if "experimental" in s_lower:
        for inst in installed:
            if "experimental" in inst.lower():
                return inst
                
    # Specific numbers (e.g. "9.0" or "8.0")
    num_match = re.search(r'(?:proton\s*)?(\d+)[\.-](\d+)', s_lower)
    if num_match:
        version_prefix = f"proton {num_match.group(1)}.{num_match.group(2)}"
        matching_inst = [inst for inst in installed if inst.lower().startswith(version_prefix) or f"proton-{num_match.group(1)}.{num_match.group(2)}" in inst.lower()]
        if matching_inst:
            return matching_inst[-1]
            
    return None


def proton_matches(suggested, installed, report_count, vote_score, total_score):
    installed_match = match_version(suggested, installed)
    accepted_match = installed_match
    if report_count < 2 or total_score <= 0 or vote_score / total_score < 0.35:
        accepted_match = None
    return installed_match, accepted_match

def sort_scored_reports(scored_reports):
    """Rank by match score, then newest report, independent of API order."""
    return sorted(scored_reports,
                  key=lambda item: (item[0], item[1].get("timestamp", 0)),
                  reverse=True)


def config_value(value):
    """Serialize a value for LaunchLayer's non-evaluating env parser."""
    value = str(value)
    if any(char in value for char in ("\0", "\r", "\n", "#", "'", '"')):
        raise ValueError("unsafe config value")
    if re.fullmatch(r'[A-Za-z0-9_.,:+/@%=-]*', value):
        return value
    return f'"{value}"'


@contextmanager
def config_lock(file_path):
    lock = open(f"{file_path}.lock", "a+", encoding="utf-8")
    try:
        if fcntl is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        yield
    finally:
        if fcntl is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()


def apply_config_updates_atomic(file_path, updates, app_id):
    """Apply a recommendation batch under the shared per-file lock."""
    directory = os.path.dirname(file_path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    with config_lock(file_path):
        if os.path.isfile(file_path):
            with open(file_path, encoding="utf-8") as source:
                lines = source.readlines()
        else:
            lines = [f"# AppID {app_id} - ProtonDB recommendations\n",
                     "INCLUDE=presets/standard.env\n", "\n"]

        pending = dict(updates)
        output = []
        index = 0
        while index < len(lines):
            line = lines[index]
            managed = re.match(r'^# launchlayer:protondb-managed ([A-Za-z_][A-Za-z0-9_]*)\s*$', line)
            if managed and index + 1 < len(lines):
                key = managed.group(1)
                value_line = lines[index + 1]
                value_match = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)=', value_line)
                if value_match and value_match.group(1) == key:
                    if key in pending:
                        output.append(f"# launchlayer:protondb-managed {key}\n")
                        output.append(f"{key}={config_value(pending.pop(key))}\n")
                    index += 2
                    continue
            match = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)=', line)
            key = match.group(1) if match else None
            if key in pending:
                # An unmarked value belongs to the user. Do not replace or claim it.
                pending.pop(key)
            output.append(line)
            index += 1
        if output and not output[-1].endswith("\n"):
            output[-1] += "\n"
        for key in sorted(pending):
            output.append(f"# launchlayer:protondb-managed {key}\n")
            output.append(f"{key}={config_value(pending[key])}\n")

        if output == lines:
            return False

        fd, temp_path = tempfile.mkstemp(prefix=".launchlayer-env.", dir=directory)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as target:
                target.writelines(output)
                target.flush()
                os.fsync(target.fileno())
            os.replace(temp_path, file_path)
            return True
        except Exception:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass
            raise


def main():
    if len(sys.argv) < 5:
        print("Usage: protondb_suggest.py <appid> <env_json> <apply> <games_dir>", file=sys.stderr)
        sys.exit(1)
        
    app_id = sys.argv[1]
    env_json_str = sys.argv[2]
    apply_flag = sys.argv[3] == "1"
    games_dir = sys.argv[4]
    game_native = len(sys.argv) >= 6 and sys.argv[5] == "1"
    
    try:
        env_info = json.loads(env_json_str)
    except Exception as e:
        print(f"Error parsing environment JSON: {e}", file=sys.stderr)
        sys.exit(1)
        
    steam_root = env_info.get("steam_root")
    host_gpu = env_info.get("gpu_vendor", "unknown").lower()
    host_cpu = detect_host_cpu(env_info)
            
    host_distro = detect_host_distro(env_info)
    host_os_family = env_info.get("os_family", "unknown").lower()
    is_steam_deck = env_info.get("steam_deck", False) or "steam-deck" in str(env_info.get("profiles", "")).lower()
    
    # 1. Fetch game summary
    summary_url = f"https://www.protondb.com/api/v1/reports/summaries/{app_id}.json"
    try:
        summary = fetch_json(summary_url)
    except Exception as e:
        print(f"{RED}{BOLD}No ProtonDB reports or ratings found for AppID {app_id}.{RESET}", file=sys.stderr)
        print(f"{DIM}({e}){RESET}", file=sys.stderr)
        sys.exit(1)
        
    tier = summary.get("tier", "pending").lower()
    trending_tier = summary.get("trendingTier", "pending").lower()
    confidence = summary.get("confidence", "unknown").upper()
    score = summary.get("score", 0.0)
    total_reports = summary.get("total", 0)
    
    tier_color = TIER_COLORS.get(tier, RESET)
    trend_color = TIER_COLORS.get(trending_tier, RESET)
    
    # Fetch counts.json
    counts_url = "https://www.protondb.com/data/counts.json"
    try:
        counts = fetch_json(counts_url)
    except Exception as e:
        print(f"Error fetching counts data from ProtonDB: {e}", file=sys.stderr)
        sys.exit(1)
        
    global_reports = counts["reports"]
    global_timestamp = counts["timestamp"]
    
    # Compute hash and fetch all reports
    reports_hash = get_hash(app_id, global_reports, global_timestamp, "all")
    reports_url = f"https://www.protondb.com/data/reports/all-devices/app/{reports_hash}.json"
    
    try:
        reports_data = fetch_json(reports_url)
    except Exception as e:
        print(f"Error fetching reports details: {e}", file=sys.stderr)
        sys.exit(1)
        
    reports = reports_data.get("reports", [])
    if not reports:
        print(f"{YELLOW}ProtonDB reports file is empty for AppID {app_id}.{RESET}")
        sys.exit(0)
        
    # Process reports and rank by match score
    current_time = time.time()
    scored_reports = []
    
    for r in reports:
        responses = r.get("responses", {})
        device = r.get("device", {})
        inferred = device.get("inferred", {}).get("steam", {})
        
        # Check if report has comments or launch options
        has_content = (responses.get("launchOptions") or 
                       (responses.get("notes") and responses.get("notes").get("verdict")) or 
                       responses.get("concludingNotes"))
        if not has_content:
            continue
            
        rep_timestamp = r.get("timestamp", 0)
        age_days = (current_time - rep_timestamp) / (24 * 3600)
        
        # Scoring components
        rep_score = 1.0
        
        # Recency
        if age_days <= 90:
            rep_score += 2.0
        elif age_days <= 180:
            rep_score += 1.0
        elif age_days <= 365:
            rep_score += 0.5
        elif age_days > 730:
            rep_score -= 2.0  # discount very old reports
            
        # Hardware / Device match
        rep_hardware = device.get("hardwareType", "pc")
        if is_steam_deck:
            if rep_hardware == "steamDeck":
                rep_score += 4.0
            else:
                rep_score -= 1.0
        else:
            if rep_hardware == "pc":
                rep_score += 2.0
            else:
                rep_score -= 2.0
                
        # GPU Match
        rep_gpu = inferred.get("gpu", "").lower()
        rep_score += gpu_match_bonus(host_gpu, rep_gpu)
                
        # CPU Match
        rep_cpu = inferred.get("cpu", "").lower()
        if host_cpu != "unknown":
            if host_cpu in rep_cpu or (host_cpu == "amd" and "ryzen" in rep_cpu):
                rep_score += 1.0
                
        # Distro / OS match
        rep_os = inferred.get("os", "").lower()
        if host_distro != "unknown":
            if host_distro in rep_os:
                rep_score += 1.0
            elif host_os_family != "unknown":
                # Check families
                arch_distros = ["arch", "cachy", "manjaro", "garuda", "endeavour"]
                fedora_distros = ["fedora", "nobara", "bazzite", "aurora", "bluefin"]
                debian_distros = ["ubuntu", "debian", "pop", "mint"]
                
                if any(x in host_distro for x in arch_distros) and any(x in rep_os for x in arch_distros):
                    rep_score += 2.0
                elif any(x in host_distro for x in fedora_distros) and any(x in rep_os for x in fedora_distros):
                    rep_score += 2.0
                elif any(x in host_distro for x in debian_distros) and any(x in rep_os for x in debian_distros):
                    rep_score += 2.0
                    
        # Verdict boost
        if responses.get("verdict") == "yes":
            rep_score += 1.0
            
        scored_reports.append((rep_score, r))
        
    # Sort reports by score descending
    scored_reports = sort_scored_reports(scored_reports)
    
    # Filter reports with score > 0, fallback to top 20 recency if none
    valid_reports = actionable_reports(scored_reports, now=current_time)
    display_reports = valid_reports
    if not display_reports:
        display_reports = sorted(scored_reports, key=lambda x: x[1].get("timestamp", 0), reverse=True)[:20]
        
    # 1. Aggregate Proton versions
    proton_votes = defaultdict(float)
    proton_report_counts = defaultdict(int)
    total_score = sum(sr[0] for sr in valid_reports) or 1.0
    
    for score_weight, r in valid_reports:
        responses = r.get("responses", {})
        ver = responses.get("customProtonVersion") or responses.get("protonVersion")
        if ver:
            # Normalize common names
            ver_norm = ver.strip()
            # remove build numbers, e.g. Proton GE-Proton9-22 (Stable) -> GE-Proton9-22
            ver_norm = re.sub(r'\s*\(.*\)', '', ver_norm)
            proton_votes[ver_norm] += score_weight
            proton_report_counts[ver_norm] += 1
            
    # Sort proton versions by score
    sorted_proton = sorted(proton_votes.items(),
                           key=lambda item: (-item[1], version_sort_key(item[0])))
    
    # 2. Aggregate launch options
    wrapper_votes = defaultdict(float)
    wrapper_report_counts = defaultdict(int)
    env_votes = defaultdict(lambda: defaultdict(float))
    env_report_counts = defaultdict(lambda: defaultdict(int))
    arg_votes = defaultdict(float)
    arg_report_counts = defaultdict(int)
    
    for score_weight, r in valid_reports:
        opts_str = r.get("responses", {}).get("launchOptions", "")
        wrappers, env_vars, extra_args = parse_launch_options(opts_str)
        
        for w in wrappers:
            wrapper_votes[w] += score_weight
            wrapper_report_counts[w] += 1
        for k, v in env_vars.items():
            env_votes[k][v] += score_weight
            env_report_counts[k][v] += 1
        if extra_args:
            arg_group = tuple(extra_args)
            arg_votes[arg_group] += score_weight
            arg_report_counts[arg_group] += 1
            
    # Collect recommendations with >20% vote thresholds
    rec_wrappers = []
    for w, w_score in sorted(wrapper_votes.items()):
        if wrapper_report_counts[w] >= 2 and w_score / total_score >= 0.20:
            rec_wrappers.append(w)
            
    rec_env_vars = {}
    for k, val_dict in env_votes.items():
        # find best value
        best_val, val_score = sorted(val_dict.items(), key=lambda item: (-item[1], item[0]))[0]
        if (is_allowed_recommendation_value(k, best_val)
                and (is_allowed_config_key(k) or is_compatibility_key(k))
                and has_apply_consensus(k, val_score, total_score,
                                        env_report_counts[k][best_val])):
            rec_env_vars[k] = best_val
            
    rec_args = []
    if arg_votes:
        arg_group, arg_score = sorted(arg_votes.items(), key=lambda item: (-item[1], item[0]))[0]
        if has_argument_consensus(arg_score, total_score, arg_report_counts[arg_group]):
            rec_args = list(arg_group)
            
    # Check installed proton versions
    installed_proton_tools = list_installed_proton_tools(steam_root)
    
    suggested_proton = None
    installed_proton_match = None
    matched_installed_proton = None
    if sorted_proton:
        suggested_proton = sorted_proton[0][0]
        installed_proton_match, matched_installed_proton = proton_matches(
            suggested_proton, installed_proton_tools,
            proton_report_counts[suggested_proton],
            proton_votes[suggested_proton], total_score)
        
    # Render Output
    print(f"\n{BOLD}{CYAN}=== ProtonDB Tuning Engine ==={RESET}")
    print(f"  {BOLD}Game AppID{RESET}: {app_id}")
    print(f"  {BOLD}ProtonDB Tier{RESET}: {tier_color}{tier.upper()}{RESET} ({trend_color}{trending_tier.upper()} trend{RESET}) | {BOLD}Confidence{RESET}: {confidence}")
    print(f"  {BOLD}Total reports parsed{RESET}: {total_reports} (analyzed top {len(valid_reports)} matching/recent comments)")
    print(f"  {BOLD}Host system detected{RESET}: CPU={host_cpu.upper()} · GPU={host_gpu.upper()} · OS={host_distro} · Handheld={is_steam_deck}")
    print()
    
    print(f"{BOLD}{GREEN}Recommended Compatibility Layer:{RESET}")
    if suggested_proton:
        pct = int((proton_votes[suggested_proton] / total_score) * 100)
        print(f"  --> {BOLD}{suggested_proton}{RESET} ({pct}% match weight)")
        if matched_installed_proton:
            print(f"      {GREEN}Installed and matched: '{matched_installed_proton}'{RESET}")
        elif installed_proton_match:
            print(f"      {YELLOW}Installed as '{installed_proton_match}', but lacks enough fresh matching reports{RESET}")
        else:
            # check if any GE tool matches
            if "ge" in suggested_proton.lower():
                installed_ge = [inst for inst in installed_proton_tools if "ge-proton" in inst.lower()]
                if installed_ge:
                    print(f"      {YELLOW}'{suggested_proton}' lacks enough fresh matching reports; nearest installed is '{installed_ge[-1]}'{RESET}")
                else:
                    print(f"      {RED}Not installed! Please install '{suggested_proton}' via ProtonUp-Qt.{RESET}")
            else:
                # check experimental
                if "experimental" in suggested_proton.lower():
                    installed_exp = [inst for inst in installed_proton_tools if "experimental" in inst.lower()]
                    if installed_exp:
                        print(f"      {YELLOW}Installed as '{installed_exp[-1]}', but lacks enough fresh matching reports{RESET}")
                    else:
                        print(f"      {RED}Not installed! Please install '{suggested_proton}' via Steam.{RESET}")
                else:
                    print(f"      {RED}Not installed! Please install '{suggested_proton}' via Steam.{RESET}")
    else:
        print("  --> Use standard Steam system default (no clear preference)")
        
    print()
    print(f"{BOLD}{GREEN}Recommended Launch Layer Adjustments:{RESET}")
    has_tuning = False
    
    for w in rec_wrappers:
        print(f"  {BOLD}{w}=1{RESET} (Wrapper script toggle)")
        has_tuning = True
        
    for k, v in sorted(rec_env_vars.items()):
        kind = "Compatibility fallback" if is_compatibility_key(k) else "Environment variable override"
        print(f"  {BOLD}{k}={v}{RESET} ({kind})")
        has_tuning = True
        
    if rec_args:
        args_val = " ".join(rec_args)
        print(f"  {BOLD}GAME_EXTRA_ARGS=\"{args_val}\"{RESET} (Command-line arguments)")
        has_tuning = True
        
    if not has_tuning:
        print(f"  {DIM}No special launch options required (runs clean out-of-the-box){RESET}")
    print()
    
    print(f"{BOLD}{CYAN}Key Community Submitter Comments (Similar Hardware):{RESET}")
    printed_comments = 0
    for score_weight, r in display_reports:
        if printed_comments >= 3:
            break
        responses = r.get("responses", {})
        verdict_notes = responses.get("notes", {}).get("verdict", "")
        concluding = responses.get("concludingNotes", "")
        
        text = concluding if concluding else verdict_notes
        if not text:
            continue
            
        device = r.get("device", {})
        inferred = device.get("inferred", {}).get("steam", {})
        rep_gpu = inferred.get("gpu", "unknown GPU")
        rep_os = inferred.get("os", "Linux")
        rep_timestamp = r.get("timestamp", 0)
        dt = datetime.fromtimestamp(rep_timestamp, timezone.utc).strftime('%Y-%m-%d')
        
        # Clean comment formatting
        clean_text = text.replace("\n", "\n      ")
        # shorten if very long
        if len(clean_text) > 400:
            clean_text = clean_text[:400] + "..."
            
        print(f"  • [{DIM}{dt}{RESET} · {BLUE}{rep_os}{RESET} · {YELLOW}{rep_gpu}{RESET}] (Score Match: {score_weight:.1f})")
        print(f"    \"{clean_text}\"")
        print()
        printed_comments += 1
        
    if apply_flag:
        config_file = os.path.join(games_dir, f"{app_id}.env")
        print(f"{BOLD}Applying recommendations to config file:{RESET} {config_file}")
        
        updates = {}

        selected_proton = select_proton_override(
            suggested_proton, matched_installed_proton, game_native)
        if selected_proton:
            print(f"  Writing OVERRIDE_PROTON=\"{selected_proton}\"")
            updates["OVERRIDE_PROTON"] = selected_proton
        elif game_native and suggested_proton:
            print("  Skipping OVERRIDE_PROTON: native game configuration")
        elif matched_installed_proton and re.match(
                r'^Proton\s+\d', matched_installed_proton, re.IGNORECASE):
            print("  Using installed Valve Proton through Steam default; no permanent pin")
        elif suggested_proton:
            print(f"  Skipping OVERRIDE_PROTON: '{suggested_proton}' is unavailable or lacks consensus")
            
        # Write wrappers
        for w in ["GAMEMODE", "MANGOHUD", "GAMESCOPE"]:
            if w in rec_wrappers:
                if should_apply_wrapper(w):
                    print(f"  Writing {w}=1")
                    updates[w] = "1"
                else:
                    print(f"  Keeping {w}=1 from LaunchLayer defaults")
                
        # Write custom env vars (allowlisted only)
        for k, v in rec_env_vars.items():
            if not (is_allowed_config_key(k) or is_compatibility_key(k)):
                print(f"  Skipping disallowed key from community report: {k}")
                continue
            try:
                config_value(v)
            except ValueError:
                print(f"  Skipping {k}: value contains unsupported characters")
                continue
            print(f"  Writing {k}={config_value(v)}")
            updates[k] = v
            
        # Write args
        if rec_args:
            args_val = " ".join(rec_args)
            print(f"  Merging GAME_EXTRA_ARGS=\"{args_val}\"")
            updates["GAME_EXTRA_ARGS"] = args_val

        has_managed_settings = False
        if os.path.isfile(config_file):
            with open(config_file, encoding="utf-8") as source:
                has_managed_settings = "# launchlayer:protondb-managed " in source.read()
        changed = (apply_config_updates_atomic(config_file, updates, app_id)
                   if updates or has_managed_settings else False)
        if changed:
            print(f"\n{BOLD}{GREEN}Reconciled managed recommendations.{RESET} Inspect them with '{BOLD}launchlayer --dry-run %command%{RESET}'.")
        elif updates:
            print(f"\n{DIM}Managed recommendations are already current.{RESET}")
        else:
            print(f"\n{YELLOW}No fresh, corroborated recommendations remain.{RESET}")

if __name__ == "__main__":
    main()
