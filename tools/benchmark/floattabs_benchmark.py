#!/usr/bin/env python3
"""Local Real-Mac resource benchmark harness for FloatTabs.

The harness intentionally uses only the Python standard library and macOS built-in
commands. It never mutates FloatTabs profile data. Guided mode asks the user to
change Residency policy through the product UI, verifies the persisted setting,
then samples only processes whose launchd `responsible pid` is the current
FloatTabs host process.

Primary outputs:
- per-sample CSV
- per-capture JSON summary
- session Markdown report with automated comparisons

Run `python3 tools/benchmark/floattabs_benchmark.py --help` for usage.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
import os
import platform
import re
import shutil
import socket
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parents[2]
DEFAULT_RESULTS_ROOT = REPO_ROOT / ".benchmark-results"
PROFILE_FILE = Path.home() / "Library" / "Application Support" / "FloatTabs" / "WebAppProfiles.json"
CONTROL_INFO_FILE = Path.home() / "Library" / "Application Support" / "FloatTabs" / "BenchmarkControl.json"
DEFAULT_SAMPLE_SECONDS = 15
DEFAULT_SAMPLE_INTERVAL = 1.0
DEFAULT_SETTLE_SECONDS = 5
COLD_GRACE_SECONDS = 30
PROCINFO_REFRESH_SECONDS = 5

WEBKIT_MARKERS = (
    "com.apple.WebKit",
    "WebKit.WebContent",
    "WebKit.Networking",
    "WebKit.GPU",
)


def run_command(
    args: Sequence[str],
    *,
    check: bool = False,
    capture: bool = True,
    timeout: Optional[float] = None,
) -> subprocess.CompletedProcess:
    kwargs = {
        "text": True,
        "check": check,
        "timeout": timeout,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.STDOUT
    return subprocess.run(list(args), **kwargs)


def command_output(args: Sequence[str], default: str = "") -> str:
    try:
        completed = run_command(args, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return default
    if completed.returncode != 0:
        return default
    return (completed.stdout or "").strip()


def ensure_macos() -> None:
    if sys.platform != "darwin":
        raise RuntimeError("This benchmark harness must run on macOS.")


def human_mb(kb: float) -> str:
    return f"{kb / 1024.0:.1f} MB"


def percent(value: float) -> str:
    return f"{value:.2f}%"


def safe_float(value: str) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def percentile(values: Sequence[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * p
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def now_stamp() -> str:
    return dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")


def iso_now() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def git_value(args: Sequence[str], default: str = "unknown") -> str:
    try:
        output = command_output(["git", "-C", str(REPO_ROOT), *args])
    except OSError:
        return default
    return output or default


def system_info() -> Dict[str, object]:
    memsize = safe_float(command_output(["sysctl", "-n", "hw.memsize"], "0")) or 0
    return {
        "captured_at": iso_now(),
        "mac_model": command_output(["sysctl", "-n", "hw.model"], "unknown"),
        "chip": command_output(["sysctl", "-n", "machdep.cpu.brand_string"], "Apple Silicon / unknown"),
        "ram_bytes": int(memsize),
        "ram_gb": round(memsize / (1024 ** 3), 2) if memsize else 0,
        "macos": command_output(["sw_vers", "-productVersion"], platform.mac_ver()[0] or "unknown"),
        "power": command_output(["pmset", "-g", "batt"], "unknown").replace("\n", " | "),
        "git_branch": git_value(["branch", "--show-current"]),
        "git_sha": git_value(["rev-parse", "HEAD"]),
        "python": platform.python_version(),
    }


def load_profile_state() -> Dict[str, object]:
    if not PROFILE_FILE.exists():
        return {"version": None, "profiles": [], "lastActiveTabID": None}
    try:
        return json.loads(PROFILE_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Unable to read {PROFILE_FILE}: {exc}") from exc


def normalized_profiles() -> List[Dict[str, object]]:
    state = load_profile_state()
    profiles = list(state.get("profiles") or [])
    profiles.sort(key=lambda item: (item.get("order", 0), item.get("createdAt", "")))
    return profiles


def profile_summary(profile: Dict[str, object]) -> Dict[str, object]:
    rendering = profile.get("renderingProfile") or {}
    return {
        "id": profile.get("id"),
        "order": profile.get("order"),
        "name": profile.get("name", "Unnamed"),
        "residency": profile.get("residencyPolicy", "warm"),
        "background_media": profile.get("backgroundMediaPolicy", "pauseWhenInactive"),
        "website_mode": rendering.get("websiteMode", rendering.get("contentMode", "unknown")),
        "browser_identity": rendering.get("browserIdentity", rendering.get("browserCompatibility", "unknown")),
        "viewport_width": rendering.get("viewportWidth"),
        "viewport_height": rendering.get("viewportHeight"),
        "zoom": rendering.get("zoom"),
    }


def all_profile_summaries() -> List[Dict[str, object]]:
    return [profile_summary(profile) for profile in normalized_profiles()]


def print_profiles(profiles: Sequence[Dict[str, object]]) -> None:
    if not profiles:
        print("No persisted FloatTabs Slots found.")
        return
    print("\nCurrent FloatTabs Slots:")
    print("  #  Name                     Residency  Media                  Mode      Viewport    Zoom")
    print("  -- ------------------------ ---------- ---------------------- --------- ----------- -----")
    for index, profile in enumerate(profiles, start=1):
        name = str(profile.get("name", "Unnamed"))[:24]
        residency = str(profile.get("residency", "warm"))
        media = str(profile.get("background_media", "pauseWhenInactive"))
        mode = str(profile.get("website_mode", "unknown"))
        width = profile.get("viewport_width")
        height = profile.get("viewport_height")
        viewport = f"{int(width)}x{int(height)}" if isinstance(width, (int, float)) and isinstance(height, (int, float)) else "unknown"
        zoom = profile.get("zoom")
        zoom_text = f"{float(zoom) * 100:.0f}%" if isinstance(zoom, (int, float)) else "?"
        print(f"  {index:>2} {name:<24} {residency:<10} {media:<22} {mode:<9} {viewport:<11} {zoom_text:>5}")



def load_control_info(host_pid: int) -> Dict[str, object]:
    if not CONTROL_INFO_FILE.exists():
        raise RuntimeError(
            "FloatTabs Debug benchmark control is unavailable. Rebuild/restart the Debug app from this PR branch."
        )
    try:
        payload = json.loads(CONTROL_INFO_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Unable to read benchmark control info: {exc}") from exc
    if int(payload.get("pid", -1)) != host_pid:
        raise RuntimeError(
            f"Benchmark control belongs to PID {payload.get('pid')}, but current FloatTabs PID is {host_pid}. "
            "Quit duplicate/stale FloatTabs builds and restart the current Debug build."
        )
    if int(payload.get("protocol_version", 0)) != 1:
        raise RuntimeError("Unsupported FloatTabs benchmark control protocol version.")
    return payload


class BenchmarkControlClient:
    def __init__(self, host_pid: int) -> None:
        info = load_control_info(host_pid)
        self.host = str(info.get("host", "127.0.0.1"))
        self.port = int(info["port"])
        self.token = str(info["token"])

    def request(self, action: str, **payload: object) -> Dict[str, object]:
        request_payload = {"token": self.token, "action": action, **payload}
        encoded = (json.dumps(request_payload, separators=(",", ":")) + "\n").encode("utf-8")
        chunks: List[bytes] = []
        try:
            with socket.create_connection((self.host, self.port), timeout=5) as connection:
                connection.sendall(encoded)
                while True:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
                    if b"\n" in chunk:
                        break
        except OSError as exc:
            raise RuntimeError(f"FloatTabs benchmark control connection failed: {exc}") from exc
        try:
            response = json.loads(b"".join(chunks).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"Invalid response from FloatTabs benchmark control: {exc}") from exc
        if not response.get("ok"):
            raise RuntimeError(f"FloatTabs benchmark control rejected {action}: {response.get('error', 'unknown error')}")
        return response

    def status(self) -> Dict[str, object]:
        return dict(self.request("status").get("status") or {})

    def configure(self, slot_ids: Sequence[str], residency: str, media: str = "pauseWhenInactive") -> Dict[str, object]:
        return dict(self.request(
            "configure",
            slot_ids=list(slot_ids),
            residency=residency,
            background_media=media,
        ).get("status") or {})

    def configure_one(self, slot_id: str, residency: str, media: str) -> Dict[str, object]:
        return self.configure([slot_id], residency, media)

    def activate(self, slot_id: str) -> Dict[str, object]:
        return dict(self.request("activate", slot_id=slot_id).get("status") or {})

    def show(self) -> Dict[str, object]:
        return dict(self.request("show").get("status") or {})

    def hide(self) -> Dict[str, object]:
        return dict(self.request("hide").get("status") or {})


def control_profiles(status: Dict[str, object]) -> List[Dict[str, object]]:
    profiles = list(status.get("profiles") or [])
    profiles.sort(key=lambda item: (item.get("order", 0), item.get("name", "")))
    return profiles


def verify_control_policy(status: Dict[str, object], selected_ids: Sequence[str], expected: str) -> None:
    profiles = {str(item.get("id")): item for item in control_profiles(status)}
    mismatches = []
    for slot_id in selected_ids:
        profile = profiles.get(slot_id)
        if not profile:
            mismatches.append(f"missing {slot_id}")
            continue
        if profile.get("residency") != expected:
            mismatches.append(f"{profile.get('name')}: {profile.get('residency')}")
        if profile.get("background_media") != "pauseWhenInactive":
            mismatches.append(f"{profile.get('name')}: media={profile.get('background_media')}")
    if mismatches:
        raise RuntimeError("Automated policy verification failed: " + "; ".join(mismatches))


def find_floattabs_pids() -> List[int]:
    output = command_output(["pgrep", "-x", "FloatTabs"])
    pids: List[int] = []
    for token in output.split():
        try:
            pids.append(int(token))
        except ValueError:
            pass
    return sorted(set(pids))


def choose_host_pid(explicit_pid: Optional[int] = None) -> Tuple[int, List[str]]:
    warnings: List[str] = []
    if explicit_pid is not None:
        pids = find_floattabs_pids()
        if explicit_pid not in pids:
            raise RuntimeError(f"FloatTabs PID {explicit_pid} is not running.")
        return explicit_pid, warnings

    pids = find_floattabs_pids()
    if not pids:
        raise RuntimeError("FloatTabs is not running. Build/open the app first, then rerun the benchmark.")
    if len(pids) > 1:
        warnings.append(
            "Multiple FloatTabs processes were found; using the newest/highest PID. "
            "Quit duplicate builds for cleaner measurements."
        )
    return max(pids), warnings


def validate_sudo() -> None:
    print("\nPrecise WebKit ownership detection needs launchctl procinfo.")
    print("macOS may ask for your administrator password once; the tool never stores it.")
    completed = run_command(["sudo", "-v"], capture=False)
    if completed.returncode != 0:
        raise RuntimeError("sudo validation failed; cannot attribute WebKit processes reliably.")


def parse_procinfo(text: str) -> Dict[str, object]:
    responsible_match = re.search(r"responsible pid\s*=\s*(\d+)", text)
    bundle_match = re.search(r"bundle id\s*=\s*([^\n]+)", text)
    path_match = re.search(r"responsible path\s*=\s*([^\n]+)", text)
    return {
        "responsible_pid": int(responsible_match.group(1)) if responsible_match else None,
        "bundle_id": bundle_match.group(1).strip() if bundle_match else None,
        "responsible_path": path_match.group(1).strip() if path_match else None,
    }


def webkit_kind(bundle_id: Optional[str], command_line: str) -> str:
    value = (bundle_id or "") + " " + command_line
    if "WebContent" in value:
        return "webcontent"
    if "Networking" in value:
        return "networking"
    if "GPU" in value:
        return "gpu"
    return "webkit_other"


def candidate_webkit_processes() -> Dict[int, str]:
    output = command_output(["ps", "-axo", "pid=,comm=,args="])
    candidates: Dict[int, str] = {}
    for line in output.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(None, 1)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        remainder = parts[1]
        if any(marker in remainder for marker in WEBKIT_MARKERS):
            candidates[pid] = remainder
    return candidates


class OwnershipResolver:
    def __init__(self, host_pid: int) -> None:
        self.host_pid = host_pid
        self.owned: Dict[int, Dict[str, str]] = {}
        self.last_refresh = 0.0

    def refresh(self, force: bool = False) -> None:
        current_time = time.monotonic()
        if not force and current_time - self.last_refresh < PROCINFO_REFRESH_SECONDS:
            return
        self.last_refresh = current_time
        candidates = candidate_webkit_processes()

        alive = set(candidates)
        for pid in list(self.owned):
            if pid not in alive:
                self.owned.pop(pid, None)

        for pid, command_line in candidates.items():
            if pid in self.owned:
                continue
            completed = run_command(
                ["sudo", "-n", "/bin/launchctl", "procinfo", str(pid)],
                timeout=8,
            )
            if completed.returncode != 0:
                continue
            parsed = parse_procinfo(completed.stdout or "")
            if parsed.get("responsible_pid") != self.host_pid:
                continue
            bundle_id = parsed.get("bundle_id")
            self.owned[pid] = {
                "kind": webkit_kind(str(bundle_id) if bundle_id else None, command_line),
                "bundle_id": str(bundle_id or "unknown"),
                "command": command_line,
            }

    def snapshot(self) -> Dict[int, Dict[str, str]]:
        self.refresh()
        return dict(self.owned)


def ps_metrics(pids: Iterable[int]) -> Dict[int, Dict[str, object]]:
    unique = sorted(set(int(pid) for pid in pids if int(pid) > 0))
    if not unique:
        return {}
    pid_arg = ",".join(str(pid) for pid in unique)
    completed = run_command(["ps", "-p", pid_arg, "-o", "pid=,rss=,%cpu=,comm="])
    if completed.returncode != 0:
        return {}
    result: Dict[int, Dict[str, object]] = {}
    for line in (completed.stdout or "").splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[0])
            rss_kb = float(parts[1])
            cpu = float(parts[2])
        except ValueError:
            continue
        result[pid] = {
            "rss_kb": rss_kb,
            "cpu": cpu,
            "command": parts[3] if len(parts) > 3 else "",
        }
    return result


def aggregate_sample(
    host_pid: int,
    ownership: Dict[int, Dict[str, str]],
    process_metrics: Dict[int, Dict[str, object]],
    elapsed: float,
) -> Dict[str, object]:
    host = process_metrics.get(host_pid, {})
    groups = {
        "webcontent": {"rss_kb": 0.0, "cpu": 0.0, "count": 0},
        "networking": {"rss_kb": 0.0, "cpu": 0.0, "count": 0},
        "gpu": {"rss_kb": 0.0, "cpu": 0.0, "count": 0},
        "webkit_other": {"rss_kb": 0.0, "cpu": 0.0, "count": 0},
    }
    for pid, metadata in ownership.items():
        metrics = process_metrics.get(pid)
        if not metrics:
            continue
        kind = metadata.get("kind", "webkit_other")
        group = groups.setdefault(kind, {"rss_kb": 0.0, "cpu": 0.0, "count": 0})
        group["rss_kb"] += float(metrics.get("rss_kb", 0.0))
        group["cpu"] += float(metrics.get("cpu", 0.0))
        group["count"] += 1

    helper_rss = sum(float(group["rss_kb"]) for group in groups.values())
    helper_cpu = sum(float(group["cpu"]) for group in groups.values())
    helper_count = sum(int(group["count"]) for group in groups.values())
    host_rss = float(host.get("rss_kb", 0.0))
    host_cpu = float(host.get("cpu", 0.0))

    return {
        "elapsed_s": round(elapsed, 3),
        "host_rss_kb": round(host_rss, 2),
        "host_cpu": round(host_cpu, 3),
        "webcontent_rss_kb": round(float(groups["webcontent"]["rss_kb"]), 2),
        "webcontent_cpu": round(float(groups["webcontent"]["cpu"]), 3),
        "webcontent_count": int(groups["webcontent"]["count"]),
        "networking_rss_kb": round(float(groups["networking"]["rss_kb"]), 2),
        "networking_cpu": round(float(groups["networking"]["cpu"]), 3),
        "gpu_rss_kb": round(float(groups["gpu"]["rss_kb"]), 2),
        "gpu_cpu": round(float(groups["gpu"]["cpu"]), 3),
        "other_webkit_rss_kb": round(float(groups["webkit_other"]["rss_kb"]), 2),
        "other_webkit_cpu": round(float(groups["webkit_other"]["cpu"]), 3),
        "helper_rss_kb": round(helper_rss, 2),
        "helper_cpu": round(helper_cpu, 3),
        "helper_count": helper_count,
        "total_rss_kb": round(host_rss + helper_rss, 2),
        "total_cpu": round(host_cpu + helper_cpu, 3),
    }


def summarize_samples(samples: Sequence[Dict[str, object]]) -> Dict[str, object]:
    if not samples:
        raise RuntimeError("No samples were collected.")

    def values(key: str) -> List[float]:
        return [float(sample.get(key, 0.0)) for sample in samples]

    summary: Dict[str, object] = {"sample_count": len(samples)}
    for key in (
        "host_rss_kb",
        "webcontent_rss_kb",
        "networking_rss_kb",
        "gpu_rss_kb",
        "other_webkit_rss_kb",
        "helper_rss_kb",
        "total_rss_kb",
        "host_cpu",
        "webcontent_cpu",
        "networking_cpu",
        "gpu_cpu",
        "other_webkit_cpu",
        "helper_cpu",
        "total_cpu",
        "webcontent_count",
        "helper_count",
    ):
        metric_values = values(key)
        summary[f"{key}_avg"] = round(statistics.mean(metric_values), 3)
        summary[f"{key}_median"] = round(statistics.median(metric_values), 3)
        summary[f"{key}_p95"] = round(percentile(metric_values, 0.95), 3)
        summary[f"{key}_max"] = round(max(metric_values), 3)
    return summary


def collect_top_power_proxy(pids: Sequence[int]) -> Dict[str, object]:
    if not pids or shutil.which("top") is None:
        return {"available": False, "reason": "top unavailable"}
    args = ["top", "-l", "2", "-s", "1", "-R", "-stats", "pid,cpu,power,command"]
    for pid in sorted(set(pids)):
        args.extend(["-pid", str(pid)])
    completed = run_command(args, timeout=12)
    if completed.returncode != 0:
        return {"available": False, "reason": "top command failed"}

    latest: Dict[int, float] = {}
    for line in (completed.stdout or "").splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) < 3 or not parts[0].isdigit():
            continue
        power_value = safe_float(parts[2])
        if power_value is None:
            continue
        latest[int(parts[0])] = power_value
    if not latest:
        return {"available": False, "reason": "POWER column unavailable or non-numeric"}
    return {
        "available": True,
        "aggregate_power_proxy": round(sum(latest.values()), 3),
        "processes": len(latest),
        "note": "macOS top POWER is a relative diagnostic proxy, not joules or a product acceptance threshold.",
    }


def ensure_session_dir(results_root: Path, session_name: Optional[str]) -> Path:
    name = session_name or f"session-{now_stamp()}"
    session_dir = results_root / name
    (session_dir / "captures").mkdir(parents=True, exist_ok=True)
    return session_dir


def write_csv(path: Path, samples: Sequence[Dict[str, object]]) -> None:
    if not samples:
        return
    fieldnames = list(samples[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(samples)


def collect_capture(
    *,
    session_dir: Path,
    label: str,
    seconds: int,
    interval: float,
    host_pid: int,
    resolver: OwnershipResolver,
    policy: str,
    state: str,
    slots: int,
    selected_slot_ids: Sequence[str],
    warnings: Sequence[str],
) -> Dict[str, object]:
    print(f"\nCapturing '{label}' for {seconds}s (interval {interval:.1f}s)...")
    start = time.monotonic()
    samples: List[Dict[str, object]] = []
    next_tick = start
    while True:
        current = time.monotonic()
        elapsed = current - start
        if elapsed >= seconds and samples:
            break
        if current < next_tick:
            time.sleep(min(next_tick - current, 0.2))
            continue

        resolver.refresh(force=(not samples))
        ownership = resolver.snapshot()
        pids = [host_pid, *ownership.keys()]
        metrics = ps_metrics(pids)
        if host_pid not in metrics:
            raise RuntimeError("FloatTabs exited during measurement.")
        sample = aggregate_sample(host_pid, ownership, metrics, elapsed)
        samples.append(sample)
        print(
            f"  {elapsed:5.1f}s  total={human_mb(float(sample['total_rss_kb'])):<11} "
            f"cpu={float(sample['total_cpu']):6.2f}%  "
            f"webcontent={int(sample['webcontent_count'])} helpers={int(sample['helper_count'])}",
            flush=True,
        )
        next_tick += interval

    ownership = resolver.snapshot()
    power_proxy = collect_top_power_proxy([host_pid, *ownership.keys()])
    summary = summarize_samples(samples)
    capture = {
        "label": label,
        "captured_at": iso_now(),
        "duration_s": seconds,
        "interval_s": interval,
        "host_pid": host_pid,
        "policy": policy,
        "state": state,
        "slot_count": slots,
        "selected_slot_ids": list(selected_slot_ids),
        "profiles": all_profile_summaries(),
        "warnings": list(warnings),
        "summary": summary,
        "power_proxy": power_proxy,
        "network": {
            "available": False,
            "reason": "v1 harness intentionally omits nettop attribution until its process-level parser is validated on the target macOS version.",
        },
        "switch_latency": {
            "available": False,
            "reason": "External process sampling cannot reliably identify click-to-interactive readiness; app instrumentation is required for trustworthy latency numbers.",
        },
    }

    capture_dir = session_dir / "captures"
    write_csv(capture_dir / f"{label}.csv", samples)
    (capture_dir / f"{label}.summary.json").write_text(
        json.dumps(capture, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    write_report(session_dir)
    print(f"Capture saved: {capture_dir / (label + '.summary.json')}")
    return capture


def load_captures(session_dir: Path) -> List[Dict[str, object]]:
    captures: List[Dict[str, object]] = []
    for path in sorted((session_dir / "captures").glob("*.summary.json")):
        try:
            captures.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return captures


def capture_metric(capture: Dict[str, object], key: str) -> float:
    summary = capture.get("summary") or {}
    return float(summary.get(key, 0.0))


def latest_by_policy(captures: Sequence[Dict[str, object]], policy: str) -> Optional[Dict[str, object]]:
    matches = [capture for capture in captures if capture.get("policy") == policy]
    return matches[-1] if matches else None


def memory_cost_rating(delta_kb: float, ram_bytes: int) -> Tuple[str, float]:
    if ram_bytes <= 0:
        return "Unknown", 0.0
    ratio = (delta_kb * 1024.0) / ram_bytes * 100.0
    if ratio < 2.0:
        return "Low", ratio
    if ratio < 5.0:
        return "Moderate", ratio
    return "High", ratio


def cpu_idle_rating(cpu: float) -> str:
    if cpu <= 1.0:
        return "Good"
    if cpu <= 3.0:
        return "Watch"
    return "Investigate"


def automated_observations(
    captures: Sequence[Dict[str, object]],
    session_meta: Dict[str, object],
) -> List[str]:
    notes: List[str] = []
    ram_bytes = int((session_meta.get("system") or {}).get("ram_bytes", 0) or 0)
    hot = latest_by_policy(captures, "hot")
    warm = latest_by_policy(captures, "warm")
    cold = next((capture for capture in captures if capture.get("state") == "cold-evicted"), None) or latest_by_policy(captures, "cold")
    warm_hidden = next((capture for capture in captures if capture.get("policy") == "warm" and capture.get("state") == "hidden"), None)
    hot_hidden = next((capture for capture in captures if capture.get("policy") == "hot" and capture.get("state") == "hidden"), None)

    if hot and warm:
        hot_total = capture_metric(hot, "total_rss_kb_median")
        warm_total = capture_metric(warm, "total_rss_kb_median")
        delta = hot_total - warm_total
        rating, ram_pct = memory_cost_rating(max(delta, 0.0), ram_bytes)
        direction = "+" if delta >= 0 else ""
        notes.append(
            f"Hot vs Warm total RSS: {direction}{delta / 1024.0:.1f} MB. "
            f"Diagnostic memory premium rating: **{rating}** ({max(ram_pct, 0.0):.2f}% of physical RAM)."
        )
        hot_cpu = capture_metric(hot, "total_cpu_avg")
        warm_cpu = capture_metric(warm, "total_cpu_avg")
        notes.append(
            f"Hot vs Warm average aggregate CPU: {hot_cpu:.2f}% vs {warm_cpu:.2f}% "
            f"(delta {hot_cpu - warm_cpu:+.2f} points)."
        )

    if warm and cold:
        warm_total = capture_metric(warm, "total_rss_kb_median")
        cold_total = capture_metric(cold, "total_rss_kb_median")
        reclaimed = warm_total - cold_total
        eligible = int(cold.get("inactive_selected_slot_count", max(int(cold.get("slot_count", 0)) - 1, 0)))
        if reclaimed > 0:
            percentage = reclaimed / warm_total * 100.0 if warm_total else 0.0
            per_slot = reclaimed / eligible / 1024.0 if eligible else 0.0
            suffix = f", ~{per_slot:.1f} MB per inactive eligible Slot" if eligible else ""
            notes.append(
                f"Cold recovery vs Warm: **{reclaimed / 1024.0:.1f} MB reclaimed** "
                f"({percentage:.1f}% of Warm total RSS{suffix})."
            )
        else:
            notes.append(
                f"Cold capture did not show positive RSS recovery relative to Warm "
                f"({reclaimed / 1024.0:.1f} MB). Re-run after confirming inactive Cold Slots actually crossed the 30s grace period."
            )
        warm_wc = capture_metric(warm, "webcontent_count_median")
        cold_wc = capture_metric(cold, "webcontent_count_median")
        notes.append(
            f"Median WebContent process count Warm → Cold: {warm_wc:.0f} → {cold_wc:.0f}."
        )

    if hot_hidden:
        hot_hidden_cpu = capture_metric(hot_hidden, "total_cpu_avg")
        notes.append(
            f"Hot + hidden aggregate CPU: {hot_hidden_cpu:.2f}% — diagnostic rating **{cpu_idle_rating(hot_hidden_cpu)}**."
        )
    if warm_hidden:
        warm_hidden_cpu = capture_metric(warm_hidden, "total_cpu_avg")
        notes.append(
            f"Warm + hidden aggregate CPU: {warm_hidden_cpu:.2f}% — diagnostic rating **{cpu_idle_rating(warm_hidden_cpu)}** "
            f"(≤1% Good, 1–3% Watch, >3% Investigate)."
        )

    if not notes:
        notes.append("Not enough comparable captures yet. Run guided mode or capture Hot/Warm/Cold states in the same session.")
    notes.append(
        "These ratings are diagnostic heuristics, not release thresholds. Real-site scripts can add noise; repeat suspicious results before changing product policy."
    )
    return notes


def write_report(session_dir: Path) -> Path:
    session_meta_path = session_dir / "session.json"
    if session_meta_path.exists():
        session_meta = json.loads(session_meta_path.read_text(encoding="utf-8"))
    else:
        session_meta = {"system": system_info(), "created_at": iso_now()}
        session_meta_path.write_text(json.dumps(session_meta, indent=2, ensure_ascii=False), encoding="utf-8")
    captures = load_captures(session_dir)

    lines: List[str] = []
    lines.append("# FloatTabs Local Resource Benchmark Report")
    lines.append("")
    lines.append(f"> Session: `{session_dir.name}`")
    lines.append(f"> Generated: {iso_now()}")
    lines.append("")

    system = session_meta.get("system") or {}
    lines.append("## Environment")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|---|---|")
    lines.append(f"| Mac | {system.get('mac_model', 'unknown')} |")
    lines.append(f"| Chip | {system.get('chip', 'unknown')} |")
    lines.append(f"| RAM | {system.get('ram_gb', 0)} GB |")
    lines.append(f"| macOS | {system.get('macos', 'unknown')} |")
    lines.append(f"| Power | {system.get('power', 'unknown')} |")
    lines.append(f"| Git branch | `{system.get('git_branch', 'unknown')}` |")
    lines.append(f"| Git SHA | `{system.get('git_sha', 'unknown')}` |")
    lines.append("")

    original = session_meta.get("original_profiles") or []
    if original:
        lines.append("## Slot configuration at session start")
        lines.append("")
        lines.append("| Slot | Residency | Media | Mode | Viewport | Zoom |")
        lines.append("|---|---|---|---|---|---:|")
        for profile in original:
            width = profile.get("viewport_width")
            height = profile.get("viewport_height")
            viewport = f"{width}×{height}" if width is not None and height is not None else "?"
            zoom = profile.get("zoom")
            zoom_text = f"{float(zoom) * 100:.0f}%" if isinstance(zoom, (int, float)) else "?"
            lines.append(
                f"| {profile.get('name', 'Unnamed')} | {profile.get('residency', '?')} | "
                f"{profile.get('background_media', '?')} | {profile.get('website_mode', '?')} | {viewport} | {zoom_text} |"
            )
        lines.append("")

    lines.append("## Captures")
    lines.append("")
    if captures:
        lines.append("| Label | Policy | State | Slots | Host RSS | WebContent RSS | Total RSS | Avg CPU | p95 CPU | WebContent | POWER proxy |")
        lines.append("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for capture in captures:
            summary = capture.get("summary") or {}
            power = capture.get("power_proxy") or {}
            power_text = f"{float(power.get('aggregate_power_proxy')):.2f}" if power.get("available") else "N/A"
            lines.append(
                f"| {capture.get('label')} | {capture.get('policy')} | {capture.get('state')} | {capture.get('slot_count')} | "
                f"{float(summary.get('host_rss_kb_median', 0))/1024.0:.1f} MB | "
                f"{float(summary.get('webcontent_rss_kb_median', 0))/1024.0:.1f} MB | "
                f"**{float(summary.get('total_rss_kb_median', 0))/1024.0:.1f} MB** | "
                f"{float(summary.get('total_cpu_avg', 0)):.2f}% | "
                f"{float(summary.get('total_cpu_p95', 0)):.2f}% | "
                f"{float(summary.get('webcontent_count_median', 0)):.0f} | {power_text} |"
            )
    else:
        lines.append("No captures yet.")
    lines.append("")

    lines.append("## Automated interpretation")
    lines.append("")
    for note in automated_observations(captures, session_meta):
        lines.append(f"- {note}")
    lines.append("")

    lines.append("## Coverage / limitations")
    lines.append("")
    lines.append("- RSS and CPU are automatically sampled from the FloatTabs host plus WebKit helpers attributed by `launchctl procinfo` responsible PID.")
    lines.append("- `top` POWER is reported only as a relative proxy when the local macOS exposes a numeric POWER column.")
    lines.append("- Network is intentionally **N/A** in harness v1 until process-level `nettop` parsing is validated on the target macOS; the tool does not invent a network number.")
    lines.append("- Switch latency is intentionally **N/A** in harness v1 because an external sampler cannot reliably know when a web SPA is actually interactive. Trustworthy latency requires a small app-side instrumentation seam.")
    lines.append("- Real-site content is noisy. Repeat any surprising result before using it to change Hot/Warm/Cold product semantics.")
    lines.append("")

    lines.append("## Raw evidence")
    lines.append("")
    lines.append("Each capture has a CSV sample stream and JSON summary under `captures/` in this session directory.")
    lines.append("")

    report_path = session_dir / "report.md"
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return report_path


def create_session(results_root: Path, session_name: Optional[str]) -> Path:
    session_dir = ensure_session_dir(results_root, session_name)
    session_file = session_dir / "session.json"
    if not session_file.exists():
        payload = {
            "created_at": iso_now(),
            "system": system_info(),
            "original_profiles": all_profile_summaries(),
        }
        session_file.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    return session_dir


def wait_for_expected_policy(selected_ids: Sequence[str], expected: str, expected_media: Optional[str]) -> None:
    while True:
        profiles = {str(item.get("id")): profile_summary(item) for item in normalized_profiles()}
        mismatches = []
        for slot_id in selected_ids:
            profile = profiles.get(slot_id)
            if not profile:
                mismatches.append(f"missing Slot {slot_id}")
                continue
            if profile.get("residency") != expected:
                mismatches.append(f"{profile.get('name')}: residency={profile.get('residency')}")
            if expected_media and profile.get("background_media") != expected_media:
                mismatches.append(f"{profile.get('name')}: media={profile.get('background_media')}")
        if not mismatches:
            print("Configuration verified from WebAppProfiles.json.")
            return
        print("\nConfiguration does not match yet:")
        for mismatch in mismatches:
            print(f"  - {mismatch}")
        answer = input("Fix the settings in FloatTabs, then press Enter to re-check (or type 'skip'): ").strip().lower()
        if answer == "skip":
            print("Continuing without policy verification; report will carry current persisted settings.")
            return


def countdown(seconds: int, label: str) -> None:
    print(f"\n{label}")
    for remaining in range(seconds, 0, -1):
        if remaining == seconds or remaining <= 10 or remaining % 10 == 0:
            print(f"  {remaining}s remaining...", flush=True)
        time.sleep(1)


def prompt_selected_profiles(profiles: Sequence[Dict[str, object]], requested_count: int) -> List[Dict[str, object]]:
    if not profiles:
        raise RuntimeError("No FloatTabs profiles are available for guided benchmarking.")
    default_indices = list(range(1, min(requested_count, len(profiles)) + 1))
    default_text = ",".join(str(index) for index in default_indices)
    answer = input(
        f"\nChoose test Slot numbers, comma-separated [default {default_text}]: "
    ).strip()
    if not answer:
        indices = default_indices
    else:
        try:
            indices = [int(item.strip()) for item in answer.split(",") if item.strip()]
        except ValueError as exc:
            raise RuntimeError("Slot selection must be comma-separated numbers.") from exc
    unique_indices = []
    for index in indices:
        if index not in unique_indices:
            unique_indices.append(index)
    selected = []
    for index in unique_indices:
        if index < 1 or index > len(profiles):
            raise RuntimeError(f"Slot index {index} is out of range.")
        selected.append(dict(profiles[index - 1]))
    if not selected:
        raise RuntimeError("Select at least one Slot.")
    return selected



def persist_capture_metadata(session_dir: Path, capture: Dict[str, object], **metadata: object) -> None:
    capture.update(metadata)
    label = str(capture["label"])
    path = session_dir / "captures" / f"{label}.summary.json"
    path.write_text(json.dumps(capture, indent=2, ensure_ascii=False), encoding="utf-8")
    write_report(session_dir)


def automatic_mode(args: argparse.Namespace) -> int:
    ensure_macos()
    host_pid, warnings = choose_host_pid(args.pid)
    validate_sudo()
    resolver = OwnershipResolver(host_pid)
    resolver.refresh(force=True)
    client = BenchmarkControlClient(host_pid)
    initial_status = client.status()
    live_profiles = control_profiles(initial_status)
    if len(live_profiles) < 2:
        raise RuntimeError("Automatic benchmark needs at least two configured Slots: test Slot(s) plus one control Slot.")

    print("\nFloatTabs automatic benchmark control: CONNECTED")
    print_profiles(all_profile_summaries())
    selected = prompt_selected_profiles(all_profile_summaries(), args.slots)
    selected_ids = [str(profile.get("id")) for profile in selected]
    selected_names = [str(profile.get("name")) for profile in selected]
    unselected = [profile for profile in live_profiles if str(profile.get("id")) not in selected_ids]
    if not unselected:
        raise RuntimeError(
            "All configured Slots were selected. Leave at least one extra Slot unselected so it can stay Active while every test Slot becomes truly inactive."
        )

    initial_active = initial_status.get("active_slot_id")
    control = next(
        (profile for profile in unselected if str(profile.get("id")) == str(initial_active)),
        unselected[0],
    )
    control_id = str(control.get("id"))
    control_name = str(control.get("name", "Control"))
    original_by_id = {str(profile.get("id")): profile for profile in live_profiles}
    original_visible = bool(initial_status.get("visible", False))

    session_dir = create_session(Path(args.results_root), args.session)
    meta_path = session_dir / "session.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["automatic"] = True
    meta["automatic_selected_slots"] = selected
    meta["control_slot"] = {"id": control_id, "name": control_name}
    meta["original_active_slot_id"] = initial_active
    meta["original_panel_visible"] = original_visible
    meta["warnings"] = warnings
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n=== Fully automatic Residency benchmark ===")
    print("Test Slots: " + ", ".join(selected_names))
    print(f"Control Slot kept Active during steady-state captures: {control_name}")
    print("The harness will change only the selected Slots and will restore their original policies at the end.")

    def configure(policy: str) -> None:
        status = client.configure(selected_ids, policy, "pauseWhenInactive")
        verify_control_policy(status, selected_ids, policy)

    def activate_test_slots_then_control() -> float:
        for slot_id, name in zip(selected_ids, selected_names):
            client.activate(slot_id)
            print(f"  activated: {name}")
            time.sleep(max(args.activation_wait, 0.0))
        client.activate(control_id)
        started = time.monotonic()
        print(f"  active control: {control_name} — all selected test Slots are now inactive")
        return started

    def capture_auto(label: str, policy: str, state: str, seconds: Optional[int] = None) -> Dict[str, object]:
        capture = collect_capture(
            session_dir=session_dir,
            label=label,
            seconds=seconds if seconds is not None else args.seconds,
            interval=args.interval,
            host_pid=host_pid,
            resolver=resolver,
            policy=policy,
            state=state,
            slots=len(selected),
            selected_slot_ids=selected_ids,
            warnings=warnings,
        )
        persist_capture_metadata(
            session_dir,
            capture,
            inactive_selected_slot_count=len(selected),
            control_slot_id=control_id,
            control_slot_name=control_name,
        )
        return capture

    def settle(label: str) -> None:
        if args.settle > 0:
            countdown(args.settle, label)

    def restore() -> None:
        print("\nRestoring original FloatTabs state...")
        for slot_id in selected_ids:
            original = original_by_id.get(slot_id) or {}
            residency = str(original.get("residency", "warm"))
            media = str(original.get("background_media", "pauseWhenInactive"))
            try:
                client.configure_one(slot_id, residency, media)
            except RuntimeError as exc:
                print(f"WARNING: could not restore policy for {original.get('name', slot_id)}: {exc}")
        if initial_active:
            try:
                client.activate(str(initial_active))
            except RuntimeError as exc:
                print(f"WARNING: could not restore original active Slot: {exc}")
        try:
            if original_visible:
                client.show()
            else:
                client.hide()
        except RuntimeError as exc:
            print(f"WARNING: could not restore panel visibility: {exc}")

    try:
        client.show()

        print("\n[1/6] HOT visible")
        configure("hot")
        activate_test_slots_then_control()
        settle("Settling Hot resident state...")
        capture_auto("hot", "hot", "steady")

        print("\n[2/6] HOT hidden")
        client.hide()
        settle("Settling hidden Hot state...")
        capture_auto("hot-hidden", "hot", "hidden")
        client.show()

        print("\n[3/6] WARM visible")
        configure("warm")
        activate_test_slots_then_control()
        settle("Settling Warm detached state...")
        capture_auto("warm", "warm", "steady")

        print("\n[4/6] WARM hidden")
        client.hide()
        settle("Settling hidden Warm state...")
        capture_auto("warm-hidden", "warm", "hidden")
        client.show()

        print("\n[5/6] COLD pending")
        configure("cold")
        cold_inactive_started = activate_test_slots_then_control()
        cold_started_wall = iso_now()
        settle("Settling Cold-pending state while all selected Slots remain inactive...")
        pending_seconds = min(args.pending_seconds, max(COLD_GRACE_SECONDS - args.settle - 5, 1))
        capture = capture_auto("cold-pending", "cold", "cold-pending", pending_seconds)
        persist_capture_metadata(session_dir, capture, cold_all_inactive_started_at=cold_started_wall)

        print("\n[6/6] COLD evicted")
        target_wait = COLD_GRACE_SECONDS + args.cold_margin
        elapsed = time.monotonic() - cold_inactive_started
        remaining = max(target_wait - elapsed, 0.0)
        if remaining > 0:
            countdown(int(math.ceil(remaining)), (
                f"Waiting until every selected Cold Slot has been inactive for >{COLD_GRACE_SECONDS}s "
                f"(target {target_wait:.0f}s from final control activation)..."
            ))
        resolver.refresh(force=True)
        capture = capture_auto("cold-evicted", "cold", "cold-evicted")
        persist_capture_metadata(
            session_dir,
            capture,
            cold_all_inactive_started_at=cold_started_wall,
            cold_inactive_elapsed_before_capture_s=round(time.monotonic() - cold_inactive_started, 2),
        )
    finally:
        restore()

    report_path = write_report(session_dir)
    print("\n=== Automatic benchmark complete ===")
    print(f"Report: {report_path}")
    print(f"Raw data: {session_dir / 'captures'}")
    print("Original Residency / media / active Slot / panel visibility have been restored best-effort.")
    return 0


def guided_mode(args: argparse.Namespace) -> int:
    ensure_macos()
    host_pid, warnings = choose_host_pid(args.pid)
    validate_sudo()
    resolver = OwnershipResolver(host_pid)
    resolver.refresh(force=True)

    profiles = all_profile_summaries()
    print_profiles(profiles)
    selected = prompt_selected_profiles(profiles, args.slots)
    selected_ids = [str(profile.get("id")) for profile in selected]
    selected_names = [str(profile.get("name")) for profile in selected]
    print("\nSelected test Slots: " + ", ".join(selected_names))
    if len(selected) == 1:
        warnings.append(
            "Only one test Slot was selected. Hot vs Warm inactive cost is low-confidence because the selected Slot may remain active. "
            "Use 2–3 Slots for the first comparison when possible."
        )

    session_dir = create_session(Path(args.results_root), args.session)
    session_meta_path = session_dir / "session.json"
    session_meta = json.loads(session_meta_path.read_text(encoding="utf-8"))
    session_meta["guided_selected_slots"] = selected
    session_meta["warnings"] = warnings
    session_meta_path.write_text(json.dumps(session_meta, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n=== Guided comparison ===")
    print("For clean residency comparison, use 'Pause When Inactive' during Hot/Warm/Cold captures.")
    print("The tool never edits your FloatTabs settings; it verifies what the app persisted.")

    def prepare(policy: str, extra: str) -> None:
        print(f"\n--- Prepare {policy.upper()} ---")
        print(f"For these Slots: {', '.join(selected_names)}")
        print(f"1. Right-click each Slot → Residency → {policy.capitalize()}")
        print("2. Background Media → Pause When Inactive")
        print("3. Click each selected Slot once so its WebView exists in this app process.")
        print("4. Finish on the FIRST selected Slot and stop interacting with the pages.")
        if extra:
            print(extra)
        input("When ready, press Enter: ")
        wait_for_expected_policy(selected_ids, policy, "pauseWhenInactive")
        if args.settle > 0:
            countdown(args.settle, f"Settling for {args.settle}s...")

    prepare("hot", "Hot Slots should remain attached after you switch among them.")
    collect_capture(
        session_dir=session_dir,
        label="hot",
        seconds=args.seconds,
        interval=args.interval,
        host_pid=host_pid,
        resolver=resolver,
        policy="hot",
        state="steady",
        slots=len(selected),
        selected_slot_ids=selected_ids,
        warnings=warnings,
    )

    prepare("warm", "Warm inactive Slots should detach but remain pooled.")
    collect_capture(
        session_dir=session_dir,
        label="warm",
        seconds=args.seconds,
        interval=args.interval,
        host_pid=host_pid,
        resolver=resolver,
        policy="warm",
        state="steady",
        slots=len(selected),
        selected_slot_ids=selected_ids,
        warnings=warnings,
    )

    print("\n--- Hidden-panel idle capture (Warm) ---")
    print("Hide FloatTabs with your normal global shortcut. Do not interact with the hidden app.")
    input("After the panel is hidden, press Enter here: ")
    collect_capture(
        session_dir=session_dir,
        label="warm-hidden",
        seconds=args.seconds,
        interval=args.interval,
        host_pid=host_pid,
        resolver=resolver,
        policy="warm",
        state="hidden",
        slots=len(selected),
        selected_slot_ids=selected_ids,
        warnings=warnings,
    )
    print("Show FloatTabs again before continuing.")
    input("Press Enter after FloatTabs is visible again: ")

    prepare(
        "cold",
        "Cold releases only INACTIVE Slots. The first selected Slot remains Active; the other selected Slots are eligible for eviction.",
    )
    countdown(COLD_GRACE_SECONDS + 5, "Waiting past the 30s Cold grace period. Do not switch Slots during this countdown.")
    resolver.refresh(force=True)
    collect_capture(
        session_dir=session_dir,
        label="cold",
        seconds=args.seconds,
        interval=args.interval,
        host_pid=host_pid,
        resolver=resolver,
        policy="cold",
        state="cold-evicted",
        slots=len(selected),
        selected_slot_ids=selected_ids,
        warnings=warnings,
    )

    report_path = write_report(session_dir)
    print("\n=== Guided benchmark complete ===")
    print(f"Report: {report_path}")
    print(f"Raw data: {session_dir / 'captures'}")
    print("\nYour original Slot policies were recorded in session.json/report.md. Restore any settings you changed if desired.")
    print("\nOpen the report with:")
    print(f"  open {json.dumps(str(report_path))}")
    return 0


def doctor_mode(args: argparse.Namespace) -> int:
    ensure_macos()
    print("FloatTabs Benchmark Doctor")
    print("==========================")
    for command in ("pgrep", "ps", "sysctl", "sw_vers", "pmset", "top", "git", "sudo"):
        status = shutil.which(command) or "missing"
        print(f"{command:10} {status}")
    host_pid, warnings = choose_host_pid(args.pid)
    print(f"\nFloatTabs host PID: {host_pid}")
    for warning in warnings:
        print(f"WARNING: {warning}")
    print(f"Profile file: {PROFILE_FILE} ({'found' if PROFILE_FILE.exists() else 'missing'})")
    print_profiles(all_profile_summaries())
    try:
        control = BenchmarkControlClient(host_pid)
        status = control.status()
        print(f"\nDebug benchmark control: CONNECTED (active={status.get('active_slot_id')}, visible={status.get('visible')})")
    except RuntimeError as exc:
        print(f"\nDebug benchmark control: unavailable ({exc})")
    if args.sudo:
        validate_sudo()
        resolver = OwnershipResolver(host_pid)
        resolver.refresh(force=True)
        owned = resolver.snapshot()
        counts: Dict[str, int] = {}
        for item in owned.values():
            kind = item.get("kind", "webkit_other")
            counts[kind] = counts.get(kind, 0) + 1
        print(f"\nAttributed FloatTabs WebKit helpers: {len(owned)}")
        for kind, count in sorted(counts.items()):
            print(f"  {kind}: {count}")
    else:
        print("\nRun `doctor --sudo` to verify precise WebKit helper attribution.")
    return 0


def capture_mode(args: argparse.Namespace) -> int:
    ensure_macos()
    host_pid, warnings = choose_host_pid(args.pid)
    validate_sudo()
    resolver = OwnershipResolver(host_pid)
    resolver.refresh(force=True)
    session_dir = create_session(Path(args.results_root), args.session)
    collect_capture(
        session_dir=session_dir,
        label=args.label,
        seconds=args.seconds,
        interval=args.interval,
        host_pid=host_pid,
        resolver=resolver,
        policy=args.policy,
        state=args.state,
        slots=args.slots,
        selected_slot_ids=[],
        warnings=warnings,
    )
    report_path = write_report(session_dir)
    print(f"\nReport: {report_path}")
    return 0


def report_mode(args: argparse.Namespace) -> int:
    session_dir = Path(args.session_dir).expanduser().resolve()
    if not session_dir.exists():
        raise RuntimeError(f"Session directory does not exist: {session_dir}")
    report_path = write_report(session_dir)
    print(report_path)
    return 0


def self_test_mode() -> int:
    fixture = """
    responsible pid = 89508
    responsible path = /tmp/FloatTabs.app/Contents/MacOS/FloatTabs
    bundle id = com.apple.WebKit.WebContent
    """
    parsed = parse_procinfo(fixture)
    assert parsed["responsible_pid"] == 89508
    assert parsed["bundle_id"] == "com.apple.WebKit.WebContent"
    assert webkit_kind(str(parsed["bundle_id"]), "") == "webcontent"
    assert percentile([1, 2, 3, 4, 5], 0.95) == 4.8
    framed = (json.dumps({"token": "x", "action": "status"}, separators=(",", ":")) + "\n").encode("utf-8")
    assert framed.endswith(b"\n")

    sample = {
        "elapsed_s": 0,
        "host_rss_kb": 100,
        "host_cpu": 1,
        "webcontent_rss_kb": 200,
        "webcontent_cpu": 2,
        "webcontent_count": 1,
        "networking_rss_kb": 50,
        "networking_cpu": 0.5,
        "gpu_rss_kb": 25,
        "gpu_cpu": 0.25,
        "other_webkit_rss_kb": 0,
        "other_webkit_cpu": 0,
        "helper_rss_kb": 275,
        "helper_cpu": 2.75,
        "helper_count": 3,
        "total_rss_kb": 375,
        "total_cpu": 3.75,
    }
    summary = summarize_samples([sample, dict(sample)])
    assert summary["total_rss_kb_median"] == 375
    assert summary["helper_count_avg"] == 3

    print("FloatTabs benchmark harness self-test: PASS")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Measure FloatTabs host + responsible WebKit resource usage and generate a Markdown report."
    )
    parser.add_argument("--self-test", action="store_true", help="Run parser/report unit self-tests and exit.")
    subparsers = parser.add_subparsers(dest="command")

    doctor = subparsers.add_parser("doctor", help="Check local benchmark prerequisites and FloatTabs process attribution.")
    doctor.add_argument("--pid", type=int, default=None, help="Explicit FloatTabs host PID when multiple builds are running.")
    doctor.add_argument("--sudo", action="store_true", help="Also validate launchctl-based WebKit process attribution.")

    capture = subparsers.add_parser("capture", help="Capture one named steady-state resource window.")
    capture.add_argument("label", help="Capture label, for example hot-3 or warm-hidden.")
    capture.add_argument("--session", default=None, help="Session directory name under the results root.")
    capture.add_argument("--results-root", default=str(DEFAULT_RESULTS_ROOT))
    capture.add_argument("--seconds", type=int, default=DEFAULT_SAMPLE_SECONDS)
    capture.add_argument("--interval", type=float, default=DEFAULT_SAMPLE_INTERVAL)
    capture.add_argument("--pid", type=int, default=None)
    capture.add_argument("--policy", choices=["hot", "warm", "cold", "mixed", "baseline"], default="mixed")
    capture.add_argument("--state", choices=["active", "steady", "hidden", "cold-evicted", "other"], default="steady")
    capture.add_argument("--slots", type=int, default=0, help="Number of Slots represented by this capture.")

    automatic = subparsers.add_parser("auto", help="Fully automatic Hot/Warm/Cold benchmark through the Debug in-app control channel.")
    automatic.add_argument("--session", default=None, help="Optional stable session name. Defaults to timestamp.")
    automatic.add_argument("--results-root", default=str(DEFAULT_RESULTS_ROOT))
    automatic.add_argument("--slots", type=int, default=2, help="Default number of test Slots to preselect; one extra unselected control Slot is required.")
    automatic.add_argument("--seconds", type=int, default=DEFAULT_SAMPLE_SECONDS)
    automatic.add_argument("--interval", type=float, default=DEFAULT_SAMPLE_INTERVAL)
    automatic.add_argument("--settle", type=int, default=DEFAULT_SETTLE_SECONDS)
    automatic.add_argument("--activation-wait", type=float, default=1.0, help="Seconds to wait after automatically activating each test Slot.")
    automatic.add_argument("--pending-seconds", type=int, default=8, help="Short capture window before Cold eviction.")
    automatic.add_argument("--cold-margin", type=int, default=7, help="Extra seconds beyond the 30s Cold grace before the evicted capture.")
    automatic.add_argument("--pid", type=int, default=None)

    guided = subparsers.add_parser("guided", help="Legacy manual Hot → Warm → hidden → Cold comparison.")
    guided.add_argument("--session", default=None, help="Optional stable session name. Defaults to timestamp.")
    guided.add_argument("--results-root", default=str(DEFAULT_RESULTS_ROOT))
    guided.add_argument("--slots", type=int, default=3, help="Default number of test Slots to preselect in the prompt.")
    guided.add_argument("--seconds", type=int, default=DEFAULT_SAMPLE_SECONDS)
    guided.add_argument("--interval", type=float, default=DEFAULT_SAMPLE_INTERVAL)
    guided.add_argument("--settle", type=int, default=DEFAULT_SETTLE_SECONDS)
    guided.add_argument("--pid", type=int, default=None)

    report = subparsers.add_parser("report", help="Regenerate Markdown report for an existing session directory.")
    report.add_argument("session_dir")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.self_test:
            return self_test_mode()
        if args.command == "doctor":
            return doctor_mode(args)
        if args.command == "capture":
            return capture_mode(args)
        if args.command == "auto":
            return automatic_mode(args)
        if args.command == "guided":
            return guided_mode(args)
        if args.command == "report":
            return report_mode(args)
        parser.print_help()
        return 2
    except KeyboardInterrupt:
        print("\nBenchmark cancelled.", file=sys.stderr)
        return 130
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
