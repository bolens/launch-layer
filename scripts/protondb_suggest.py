#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
import re
import os
import shlex
import time
from datetime import datetime
from collections import defaultdict

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
    return sorted(list(installed))

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


# Mirrors lib/keys.sh known_config_key allowlist for --apply writes.
_KNOWN_CONFIG_KEYS = {
    "BENCHMARK", "GAMEMODE", "MANGOHUD", "MANGOHUD_LOG", "MANGOHUD_CONFIG", "MANGOHUD_CONFIGFILE",
    "NETWORK_TUNE", "DEBUG", "X3D_CPUS", "GAME_NIC", "GAMESCOPE", "GAMESCOPE_W", "GAMESCOPE_H", "GAMESCOPE_R",
    "GAMESCOPE_ADAPTIVE_SYNC", "GAMESCOPE_EXPOSE_WAYLAND", "GAMESCOPE_FSR", "GAMESCOPE_FSR_SHARPNESS",
    "SHADER_CACHE_CHECK", "SHADER_CACHE_MAX_GB", "SHADER_CACHE_TRIM", "SHADER_CACHE_CHECK_INTERVAL_HOURS",
    "COMPATDATA_CHECK", "COMPATDATA_MAX_GB", "COMPATDATA_TRIM", "VM_MAX_MAP_COUNT_MIN", "VM_MAX_MAP_COUNT_FIX",
    "VRAM_HOG_UNITS", "VRAM_HOGS", "VRAM_HOG_PIDS", "LAUNCH_WATCHDOG", "LAUNCH_WRAPPERS", "LAUNCH_WRAPPERS_BEFORE",
    "GAME_EXTRA_ARGS", "UNSET_VARS", "FORCE_NATIVE", "FORCE_PROTON", "VRAM_PREFLIGHT_MIN_MB",
    "PIPEWIRE_LOW_LATENCY", "LAUNCH_LOG_MAX_LINES", "PRE_LAUNCH_CMD", "POST_LAUNCH_CMD",
    "DISK_PREFLIGHT_MIN_GB", "GPU_POWER_CHECK", "NVIDIA_POWER_MODE", "CONCURRENT_LAUNCH_GUARD", "GPU_VRAM_PROCESS_MIN_MB",
    "DISABLE_CPU_AFFINITY", "GAME_PERFORMANCE", "CPU_AFFINITY_RANGE", "DISABLE_NIC_EEE", "DISABLE_WIFI_POWER_SAVE",
    "MALLOC_ALLOCATOR", "ENABLE_HDR", "GAMESCOPE_HDR", "DISK_TUNE", "OVERRIDE_PROTON", "DLSS_SWAPPER",
    "PROTON_DLSS_UPGRADE", "PROTON_FSR4_UPGRADE", "PROTON_XESS_UPGRADE", "SHADER_CACHE_BOOST",
    "LD_BIND_NOW", "VKBASALT", "LATENCYFLEX", "DISABLE_VBLANK",
    "DISABLE_STEAM_DECK", "FRAME_RATE", "INCLUDE",
    "LSFG_VK", "OBS_VKCAPTURE", "DISCORD_IPC", "REPLAY_CAPTURE", "REPLAY_TOOL",
    "BLOCK_INTERNET", "CONTY", "SPECIAL_K", "RESHADE", "DEPTH3D", "WINE_FSR",
    "FLAWLESS_WIDESCREEN", "FWS", "OPENVR_FSR", "GEO11", "SBS_VR", "FLAT2VR",
    "PLAYTIME_LOG", "CRASH_GUESS", "SPECIALTY_RUNTIME", "SKIF", "VALVEPLUG",
    "GAMESCOPE_NESTED_FIX", "GAMESCOPE_FRAME_LIMIT", "GAMESCOPE_FILTER",
    "VKBASALT_CONFIG_FILE", "SHADER_CACHE_BOOST", "SHADER_CACHE_BOOST_GB",
}
_ALLOWED_PREFIXES = (
    "PROTON_", "DXVK_", "VKD3D_", "__GL_", "__VK_", "WINE", "STEAM_", "SDL_", "MESA_", "mesa_", "RADV_", "AMD_", "INTEL_",
)
_BLOCKED_APPLY_KEYS = {
    "LD_PRELOAD", "LD_LIBRARY_PATH", "PATH", "HOME", "USER", "SHELL", "PWD", "OLDPWD",
    "SSH_AUTH_SOCK", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR",
}


def is_allowed_config_key(key: str) -> bool:
    if not key or key in _BLOCKED_APPLY_KEYS:
        return False
    if key in _KNOWN_CONFIG_KEYS:
        return True
    return any(key.startswith(prefix) for prefix in _ALLOWED_PREFIXES)


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
        
    options_str = options_str.replace("%command%", " ")
    try:
        tokens = shlex.split(options_str)
    except Exception:
        tokens = options_str.split()
        
    for token in tokens:
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
        elif token.startswith('-') or token.startswith('+'):
            extra_args.append(token)
            
    return wrappers, env_vars, extra_args

def match_version(suggested, installed):
    if not suggested:
        return None
    s_lower = suggested.lower()
    
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
    num_match = re.search(r'proton\s*(\d+)[\.-](\d+)', s_lower)
    if num_match:
        version_prefix = f"proton {num_match.group(1)}.{num_match.group(2)}"
        matching_inst = [inst for inst in installed if inst.lower().startswith(version_prefix) or f"proton-{num_match.group(1)}.{num_match.group(2)}" in inst.lower()]
        if matching_inst:
            return matching_inst[-1]
            
    return None

def upsert_config_file(file_path, key, value):
    lines = []
    found = False
    if os.path.isfile(file_path):
        with open(file_path, "r") as f:
            for line in f:
                if re.match(r'^\s*' + re.escape(key) + r'=', line):
                    lines.append(f"{key}={value}\n")
                    found = True
                else:
                    lines.append(line)
    if not found:
        # If it's empty or doesn't end with a newline, add one
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(f"{key}={value}\n")
        
    with open(file_path, "w") as f:
        f.writelines(lines)

def main():
    if len(sys.argv) < 5:
        print("Usage: protondb_suggest.py <appid> <env_json> <apply> <games_dir>", file=sys.stderr)
        sys.exit(1)
        
    app_id = sys.argv[1]
    env_json_str = sys.argv[2]
    apply_flag = sys.argv[3] == "1"
    games_dir = sys.argv[4]
    
    try:
        env_info = json.loads(env_json_str)
    except Exception as e:
        print(f"Error parsing environment JSON: {e}", file=sys.stderr)
        sys.exit(1)
        
    steam_root = env_info.get("steam_root")
    host_gpu = env_info.get("gpu_vendor", "unknown").lower()
    host_cpu = detect_host_cpu(env_info)
            
    host_distro = env_info.get("os_id", "unknown").lower()
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
    scored_reports.sort(key=lambda x: x[0], reverse=True)
    
    # Filter reports with score > 0, fallback to top 20 recency if none
    valid_reports = [sr for sr in scored_reports if sr[0] > 0]
    if not valid_reports:
        valid_reports = sorted(scored_reports, key=lambda x: x[1].get("timestamp", 0), reverse=True)[:20]
        
    # 1. Aggregate Proton versions
    proton_votes = defaultdict(float)
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
            
    # Sort proton versions by score
    sorted_proton = sorted(proton_votes.items(), key=lambda x: x[1], reverse=True)
    
    # 2. Aggregate launch options
    wrapper_votes = defaultdict(float)
    env_votes = defaultdict(lambda: defaultdict(float))
    arg_votes = defaultdict(float)
    
    for score_weight, r in valid_reports:
        opts_str = r.get("responses", {}).get("launchOptions", "")
        wrappers, env_vars, extra_args = parse_launch_options(opts_str)
        
        for w in wrappers:
            wrapper_votes[w] += score_weight
        for k, v in env_vars.items():
            env_votes[k][v] += score_weight
        for arg in extra_args:
            arg_votes[arg] += score_weight
            
    # Collect recommendations with >20% vote thresholds
    rec_wrappers = []
    for w, w_score in wrapper_votes.items():
        if w_score / total_score >= 0.20:
            rec_wrappers.append(w)
            
    rec_env_vars = {}
    for k, val_dict in env_votes.items():
        # find best value
        best_val, val_score = max(val_dict.items(), key=lambda x: x[1])
        if val_score / total_score >= 0.15:
            rec_env_vars[k] = best_val
            
    rec_args = []
    for arg, arg_score in arg_votes.items():
        if arg_score / total_score >= 0.15:
            rec_args.append(arg)
            
    # Check installed proton versions
    installed_proton_tools = list_installed_proton_tools(steam_root)
    
    suggested_proton = None
    matched_installed_proton = None
    if sorted_proton:
        suggested_proton = sorted_proton[0][0]
        matched_installed_proton = match_version(suggested_proton, installed_proton_tools)
        
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
        else:
            # check if any GE tool matches
            if "ge" in suggested_proton.lower():
                installed_ge = [inst for inst in installed_proton_tools if "ge-proton" in inst.lower()]
                if installed_ge:
                    matched_installed_proton = installed_ge[-1]
                    print(f"      {YELLOW}'{suggested_proton}' not found. Auto-matched nearest installed: '{matched_installed_proton}'{RESET}")
                else:
                    print(f"      {RED}Not installed! Please install '{suggested_proton}' via ProtonUp-Qt.{RESET}")
            else:
                # check experimental
                if "experimental" in suggested_proton.lower():
                    installed_exp = [inst for inst in installed_proton_tools if "experimental" in inst.lower()]
                    if installed_exp:
                        matched_installed_proton = installed_exp[-1]
                        print(f"      {GREEN}Installed and matched: '{matched_installed_proton}'{RESET}")
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
        if not is_allowed_config_key(k):
            continue
        print(f"  {BOLD}{k}={v}{RESET} (Environment variable override)")
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
    for score_weight, r in valid_reports:
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
        dt = datetime.fromtimestamp(rep_timestamp).strftime('%Y-%m-%d')
        
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
        
        # Initialize if not present
        if not os.path.isfile(config_file):
            print(f"  Creating new game config scaffold...")
            os.makedirs(games_dir, exist_ok=True)
            with open(config_file, "w") as f:
                f.write(f"# AppID {app_id} - Configured via ProtonDB Suggestions\n")
                f.write("INCLUDE=presets/standard.env\n\n")
                
        # Write Proton version
        if matched_installed_proton:
            print(f"  Writing OVERRIDE_PROTON=\"{matched_installed_proton}\"")
            upsert_config_file(config_file, "OVERRIDE_PROTON", f'"{matched_installed_proton}"')
        elif suggested_proton:
            # Write uninstalled warning but apply it anyway
            print(f"  Writing OVERRIDE_PROTON=\"{suggested_proton}\" (Note: tool may not be installed yet)")
            upsert_config_file(config_file, "OVERRIDE_PROTON", f'"{suggested_proton}"')
            
        # Write wrappers
        for w in ["GAMEMODE", "MANGOHUD", "GAMESCOPE"]:
            if w in rec_wrappers:
                print(f"  Writing {w}=1")
                upsert_config_file(config_file, w, "1")
                
        # Write custom env vars (allowlisted only)
        for k, v in rec_env_vars.items():
            if not is_allowed_config_key(k):
                print(f"  Skipping disallowed key from community report: {k}")
                continue
            print(f"  Writing {k}={v}")
            upsert_config_file(config_file, k, f'"{v}"' if not v.isdigit() else v)
            
        # Write args
        if rec_args:
            args_val = " ".join(rec_args)
            # Fetch existing GAME_EXTRA_ARGS and append/merge
            existing_args = ""
            if os.path.isfile(config_file):
                with open(config_file, "r", encoding="utf-8") as f:
                    for line in f:
                        m = re.match(r'^\s*GAME_EXTRA_ARGS=(.*)$', line)
                        if m:
                            existing_args = m.group(1).strip().strip('"\'')
                            break
            if existing_args:
                # Merge lists
                try:
                    exist_list = shlex.split(existing_args)
                except Exception:
                    exist_list = existing_args.split()
                for arg in rec_args:
                    if arg not in exist_list:
                        exist_list.append(arg)
                final_args = " ".join(exist_list)
            else:
                final_args = args_val
            print(f"  Writing GAME_EXTRA_ARGS=\"{final_args}\"")
            upsert_config_file(config_file, "GAME_EXTRA_ARGS", f'"{final_args}"')
            
        print(f"\n{BOLD}{GREEN}Configuration saved successfully!{RESET} You can run with '{BOLD}launchlayer --dry-run %command%{RESET}' to inspect.")

if __name__ == "__main__":
    main()
