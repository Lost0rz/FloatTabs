from pathlib import Path

PATH = Path("tools/benchmark/floattabs_lifecycle_benchmark.py")
README = Path("tools/benchmark/README.md")
text = PATH.read_text(encoding="utf-8")


def replace_once(old: str, new: str) -> None:
    global text
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing patch anchor:\n{old[:180]}")
    text = text.replace(old, new, 1)


def replace_between(start: str, end: str, replacement: str) -> None:
    global text
    if replacement in text:
        return
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f"missing start marker: {start}")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise SystemExit(f"missing end marker: {end}")
    text = text[:start_index] + replacement + "\n\n" + text[end_index:]


replace_once(
    "DEFAULT_INTERVAL = 2.0\n",
    "DEFAULT_INTERVAL = 2.0\nDEFAULT_STABLE_TAIL_SECONDS = 30.0\n",
)

replace_once(
    "        interval: float,\n        session_start: float,\n",
    "        interval: float,\n        stable_tail_seconds: float,\n        session_start: float,\n",
)
replace_once(
    "        self.interval = interval\n        self.session_start = session_start\n",
    "        self.interval = interval\n        self.stable_tail_seconds = max(stable_tail_seconds, interval)\n        self.session_start = session_start\n",
)
replace_once(
    "        summary = summarize_phase(phase, phase_rows)\n",
    "        summary = summarize_phase(\n            phase,\n            phase_rows,\n            stable_tail_seconds=self.stable_tail_seconds,\n        )\n",
)

summarize_replacement = '''def _tail_rows(
    rows: Sequence[Dict[str, object]],
    window_seconds: float,
) -> List[Dict[str, object]]:
    if not rows:
        return []
    end_elapsed = float(rows[-1].get("phase_elapsed_s", 0.0))
    cutoff = max(end_elapsed - max(window_seconds, 0.0), 0.0)
    selected = [row for row in rows if float(row.get("phase_elapsed_s", 0.0)) >= cutoff]
    return selected or [dict(rows[-1])]


def _median_metric(rows: Sequence[Dict[str, object]], key: str) -> float:
    values = [float(row.get(key, 0.0)) for row in rows]
    return float(core.statistics.median(values)) if values else 0.0


def _mean_metric(rows: Sequence[Dict[str, object]], key: str) -> float:
    values = [float(row.get(key, 0.0)) for row in rows]
    return float(core.statistics.mean(values)) if values else 0.0


def _p95_metric(rows: Sequence[Dict[str, object]], key: str) -> float:
    return core.percentile([float(row.get(key, 0.0)) for row in rows], 0.95) if rows else 0.0


def summarize_phase(
    phase: Phase,
    rows: Sequence[Dict[str, object]],
    *,
    stable_tail_seconds: float = DEFAULT_STABLE_TAIL_SECONDS,
) -> Dict[str, object]:
    if not rows:
        return {"label": phase.label, "sample_count": 0}

    process_summary = core.summarize_samples(rows)
    initial_resident = int(rows[0].get("tracked_resident_count", 0))

    first_release_index: Optional[int] = None
    if initial_resident > 0:
        for index, row in enumerate(rows[1:], start=1):
            if int(row.get("tracked_resident_count", 0)) < initial_resident:
                first_release_index = index
                break

    all_release_index: Optional[int] = None
    for index, row in enumerate(rows):
        if int(row.get("tracked_resident_count", 0)) == 0:
            all_release_index = index
            break

    first_release = (
        float(rows[first_release_index].get("phase_elapsed_s", 0.0))
        if first_release_index is not None
        else None
    )
    first_all_released = (
        float(rows[all_release_index].get("phase_elapsed_s", 0.0))
        if all_release_index is not None
        else None
    )
    first_hidden_grace_end = first_time(rows, lambda row: not bool(row.get("hidden_active_grace_pending", False)))
    first_pending_clear = first_time(
        rows,
        lambda row: int(row.get("pending_cold_release_count", 0)) == 0
        and int(row.get("pending_warm_release_count", 0)) == 0,
    )

    tail = _tail_rows(rows, stable_tail_seconds)
    tail_start = float(tail[0].get("phase_elapsed_s", 0.0))
    tail_end = float(tail[-1].get("phase_elapsed_s", 0.0))

    rss_before_first_release: Optional[float] = None
    if first_release_index is not None:
        before_index = max(first_release_index - 1, 0)
        rss_before_first_release = float(rows[before_index].get("total_rss_kb", 0.0))

    post_release_tail: List[Dict[str, object]] = []
    post_release_observed = 0.0
    if all_release_index is not None:
        post_release_rows = list(rows[all_release_index:])
        post_release_tail = _tail_rows(post_release_rows, stable_tail_seconds)
        post_release_observed = max(
            float(rows[-1].get("phase_elapsed_s", 0.0))
            - float(rows[all_release_index].get("phase_elapsed_s", 0.0)),
            0.0,
        )

    post_release_rss_kb: Optional[float] = None
    rss_reclaimed_mb: Optional[float] = None
    if post_release_tail:
        post_release_rss_kb = _median_metric(post_release_tail, "total_rss_kb")
        if rss_before_first_release is not None:
            rss_reclaimed_mb = (rss_before_first_release - post_release_rss_kb) / 1024.0

    start_rss = float(rows[0].get("total_rss_kb", 0.0))
    end_rss = float(rows[-1].get("total_rss_kb", 0.0))
    return {
        "label": phase.label,
        "policy": phase.policy,
        "state": phase.state,
        "duration_s": phase.duration,
        "sample_count": len(rows),
        "tracked_slot_count": len(phase.tracked_ids),
        "tracked_resident_start": initial_resident,
        "tracked_resident_end": int(rows[-1].get("tracked_resident_count", 0)),
        "first_tracked_release_s": None if first_release is None else round(first_release, 2),
        "first_all_tracked_released_s": None if first_all_released is None else round(first_all_released, 2),
        "first_hidden_grace_not_pending_s": None if first_hidden_grace_end is None else round(first_hidden_grace_end, 2),
        "first_release_queue_clear_s": None if first_pending_clear is None else round(first_pending_clear, 2),
        "total_rss_start_mb": round(start_rss / 1024.0, 2),
        "total_rss_end_mb": round(end_rss / 1024.0, 2),
        "total_rss_delta_mb": round((end_rss - start_rss) / 1024.0, 2),
        "total_rss_median_mb": round(float(process_summary.get("total_rss_kb_median", 0.0)) / 1024.0, 2),
        "total_cpu_avg": round(float(process_summary.get("total_cpu_avg", 0.0)), 3),
        "total_cpu_p95": round(float(process_summary.get("total_cpu_p95", 0.0)), 3),
        "webcontent_count_median": round(float(process_summary.get("webcontent_count_median", 0.0)), 2),
        "webcontent_count_end": int(rows[-1].get("webcontent_count", 0)),
        "stable_tail_window_s": round(float(stable_tail_seconds), 2),
        "stable_tail_observed_s": round(max(tail_end - tail_start, 0.0), 2),
        "stable_tail_sample_count": len(tail),
        "stable_tail_rss_median_mb": round(_median_metric(tail, "total_rss_kb") / 1024.0, 2),
        "stable_tail_rss_min_mb": round(min(float(row.get("total_rss_kb", 0.0)) for row in tail) / 1024.0, 2),
        "stable_tail_rss_max_mb": round(max(float(row.get("total_rss_kb", 0.0)) for row in tail) / 1024.0, 2),
        "stable_tail_cpu_avg": round(_mean_metric(tail, "total_cpu"), 3),
        "stable_tail_cpu_p95": round(_p95_metric(tail, "total_cpu"), 3),
        "stable_tail_webcontent_count_median": round(_median_metric(tail, "webcontent_count"), 2),
        "stable_tail_resident_count_median": round(_median_metric(tail, "tracked_resident_count"), 2),
        "rss_before_first_release_mb": None if rss_before_first_release is None else round(rss_before_first_release / 1024.0, 2),
        "post_release_stable_rss_mb": None if post_release_rss_kb is None else round(post_release_rss_kb / 1024.0, 2),
        "post_release_stable_cpu_avg": None if not post_release_tail else round(_mean_metric(post_release_tail, "total_cpu"), 3),
        "post_release_stable_cpu_p95": None if not post_release_tail else round(_p95_metric(post_release_tail, "total_cpu"), 3),
        "post_release_observed_s": round(post_release_observed, 2),
        "rss_reclaimed_mb": None if rss_reclaimed_mb is None else round(rss_reclaimed_mb, 2),
    }'''
replace_between("def summarize_phase(", "def release_expectation(", summarize_replacement)

report_replacement = '''def write_markdown_report(
    session_dir: Path,
    summaries: Sequence[Dict[str, object]],
    events: Sequence[Dict[str, object]],
) -> None:
    lines = [
        "# FloatTabs Long-Cycle Lifecycle Benchmark",
        "",
        f"> Generated: {core.iso_now()}",
        "",
        "## Phase summary",
        "",
        "Whole-phase CPU includes navigation/load/release spikes. `Tail` columns use only the final stable window of each phase.",
        "",
        "| Phase | State | RSS start | RSS end | Δ RSS | Whole CPU avg | Tail RSS | Tail CPU avg | Tail CPU p95 | Tracked resident | Check |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for item in summaries:
        lines.append(
            f"| {item.get('label')} | {item.get('state')} | {float(item.get('total_rss_start_mb', 0)):.1f} MB | "
            f"{float(item.get('total_rss_end_mb', 0)):.1f} MB | {float(item.get('total_rss_delta_mb', 0)):+.1f} MB | "
            f"{float(item.get('total_cpu_avg', 0)):.2f}% | {float(item.get('stable_tail_rss_median_mb', 0)):.1f} MB | "
            f"{float(item.get('stable_tail_cpu_avg', 0)):.2f}% | {float(item.get('stable_tail_cpu_p95', 0)):.2f}% | "
            f"{item.get('tracked_resident_start', 0)}→{item.get('tracked_resident_end', 0)} | {release_expectation(item)} |"
        )

    lines.extend([
        "",
        "## Eviction / reclaim detail",
        "",
        "`RSS before first release` is the sample immediately before tracked resident count first drops. `Post-release stable` is the median of the final post-release window.",
        "",
        "| Phase | First release | All released | RSS before first release | Post-release stable RSS | RSS reclaimed | Post-release observed |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ])
    release_rows = 0
    for item in summaries:
        first_release = item.get("first_tracked_release_s")
        all_release = item.get("first_all_tracked_released_s")
        if first_release is None and all_release is None:
            continue
        release_rows += 1
        first_text = f"{float(first_release):.1f}s" if isinstance(first_release, (int, float)) else "—"
        all_text = f"{float(all_release):.1f}s" if isinstance(all_release, (int, float)) else "—"
        before = item.get("rss_before_first_release_mb")
        after = item.get("post_release_stable_rss_mb")
        reclaimed = item.get("rss_reclaimed_mb")
        observed = item.get("post_release_observed_s")
        before_text = f"{float(before):.1f} MB" if isinstance(before, (int, float)) else "—"
        after_text = f"{float(after):.1f} MB" if isinstance(after, (int, float)) else "—"
        reclaimed_text = f"{float(reclaimed):+.1f} MB" if isinstance(reclaimed, (int, float)) else "—"
        observed_text = f"{float(observed):.1f}s" if isinstance(observed, (int, float)) else "—"
        lines.append(
            f"| {item.get('label')} | {first_text} | {all_text} | {before_text} | {after_text} | {reclaimed_text} | {observed_text} |"
        )
    if release_rows == 0:
        lines.append("| — | — | — | — | — | — | — |")

    tail_window = next(
        (float(item.get("stable_tail_window_s", DEFAULT_STABLE_TAIL_SECONDS)) for item in summaries if item.get("sample_count", 0)),
        DEFAULT_STABLE_TAIL_SECONDS,
    )
    lines.extend([
        "",
        "## Stable-tail interpretation",
        "",
        f"- Stable-tail target window: final **{tail_window:.0f}s** of each phase (or all available samples for shorter phases).",
        "- Use Tail CPU/RSS for long-idle comparisons; use whole-phase CPU only to understand load/switch/release cost.",
        "- For phases that fully evict tracked Slots, `Post-release stable RSS` is the better estimate of the released memory floor.",
        "- `Post-release observed` shows how much time remained after all tracked Slots were released; short windows should be repeated before tuning policy.",
        "",
        "## Product timer reference",
        "",
        f"- Cold inactive grace: {PRODUCT_COLD_GRACE_SECONDS}s.",
        f"- Warm inactive TTL: {PRODUCT_WARM_TTL_SECONDS}s.",
        f"- Selected + hidden recent-active grace: {PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS}s before its Residency policy begins.",
        "- Full baseline uses `Pause When Inactive`; background-media protection is intentionally isolated from this resource baseline.",
        "",
        "## Runtime events",
        "",
    ])
    for event in events:
        if event.get("kind") == "runtime_transition":
            lines.append(
                f"- `{float(event.get('session_elapsed_s', 0)):.1f}s` **{event.get('phase')}** — {event.get('detail')}"
            )
    lines.extend([
        "",
        "## Evidence",
        "",
        "- `lifecycle-timeline.csv`: continuous raw timeline.",
        "- `lifecycle-events.json`: detected lifecycle transitions.",
        "- `lifecycle-summary.json`: machine-readable phase summaries including stable-tail/reclaim metrics.",
        "- `lifecycle-chart.html`: local interactive-free SVG curves for RSS, CPU and resident WebViews.",
        "",
        "Do not treat one noisy real-site run as a release threshold. Repeat an anomalous phase before changing lifecycle policy.",
        "",
    ])
    (session_dir / "lifecycle-report.md").write_text("\\n".join(lines), encoding="utf-8")'''
replace_between("def write_markdown_report(", "def _svg_polyline(", report_replacement)

replace_once(
    '        "product_timers_s": {\n            "cold_grace": PRODUCT_COLD_GRACE_SECONDS,\n            "warm_ttl": PRODUCT_WARM_TTL_SECONDS,\n            "hidden_active_grace": PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS,\n        },\n',
    '        "product_timers_s": {\n            "cold_grace": PRODUCT_COLD_GRACE_SECONDS,\n            "warm_ttl": PRODUCT_WARM_TTL_SECONDS,\n            "hidden_active_grace": PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS,\n        },\n        "stable_tail_seconds": max(args.tail_seconds, args.interval),\n',
)
replace_once(
    '    print(f"Preset: {args.preset}; expected sampling time ≈ {estimate / 60.0:.1f} minutes")\n    print("Media policy is forced to Pause When Inactive for a clean Residency baseline.")\n',
    '    print(f"Preset: {args.preset}; expected sampling time ≈ {estimate / 60.0:.1f} minutes")\n    print(f"Stable-tail analysis window: {max(args.tail_seconds, args.interval):.0f}s")\n    print("Media policy is forced to Pause When Inactive for a clean Residency baseline.")\n',
)
replace_once(
    "        interval=max(args.interval, 0.5),\n        session_start=session_start,\n",
    "        interval=max(args.interval, 0.5),\n        stable_tail_seconds=max(args.tail_seconds, args.interval),\n        session_start=session_start,\n",
)
replace_once(
    '    run.add_argument("--activation-wait", type=float, default=1.5, help="Load settle time after each automatic Slot activation.")\n',
    '    run.add_argument("--activation-wait", type=float, default=1.5, help="Load settle time after each automatic Slot activation.")\n    run.add_argument("--tail-seconds", type=float, default=DEFAULT_STABLE_TAIL_SECONDS, help="Final per-phase window used for steady-state RSS/CPU statistics.")\n',
)

old_self_test = '''    phase = Phase("cold-inactive", "cold", "inactive", 60, ("a", "b"))
    sample = {
        "host_rss_kb": 100.0,
        "host_cpu": 1.0,
        "webcontent_rss_kb": 200.0,
        "webcontent_cpu": 2.0,
        "webcontent_count": 1,
        "networking_rss_kb": 50.0,
        "networking_cpu": 0.5,
        "gpu_rss_kb": 25.0,
        "gpu_cpu": 0.25,
        "other_webkit_rss_kb": 0.0,
        "other_webkit_cpu": 0.0,
        "helper_rss_kb": 275.0,
        "helper_cpu": 2.75,
        "helper_count": 3,
        "total_rss_kb": 375.0,
        "total_cpu": 3.75,
        "phase_elapsed_s": 0.0,
        "tracked_resident_count": 2,
    }
    later = dict(sample)
    later.update({"phase_elapsed_s": 35.0, "tracked_resident_count": 0, "total_rss_kb": 275.0})
    summary = summarize_phase(phase, [sample, later])
    assert summary["first_all_tracked_released_s"] == 35.0
    assert summary["tracked_resident_start"] == 2
    assert summary["tracked_resident_end"] == 0
    assert release_expectation(summary) == "PASS"
'''
new_self_test = '''    phase = Phase("cold-inactive", "cold", "inactive", 90, ("a", "b"))
    sample = {
        "host_rss_kb": 100.0,
        "host_cpu": 1.0,
        "webcontent_rss_kb": 200.0,
        "webcontent_cpu": 2.0,
        "webcontent_count": 1,
        "networking_rss_kb": 50.0,
        "networking_cpu": 0.5,
        "gpu_rss_kb": 25.0,
        "gpu_cpu": 0.25,
        "other_webkit_rss_kb": 0.0,
        "other_webkit_cpu": 0.0,
        "helper_rss_kb": 275.0,
        "helper_cpu": 2.75,
        "helper_count": 3,
        "total_rss_kb": 375.0,
        "total_cpu": 3.75,
        "phase_elapsed_s": 0.0,
        "tracked_resident_count": 2,
    }
    partial = dict(sample)
    partial.update({"phase_elapsed_s": 20.0, "tracked_resident_count": 1, "total_rss_kb": 325.0, "total_cpu": 2.0})
    released = dict(sample)
    released.update({"phase_elapsed_s": 35.0, "tracked_resident_count": 0, "total_rss_kb": 275.0, "total_cpu": 1.0})
    steady_a = dict(sample)
    steady_a.update({"phase_elapsed_s": 50.0, "tracked_resident_count": 0, "total_rss_kb": 260.0, "total_cpu": 0.5})
    steady_b = dict(sample)
    steady_b.update({"phase_elapsed_s": 70.0, "tracked_resident_count": 0, "total_rss_kb": 250.0, "total_cpu": 0.25})
    summary = summarize_phase(
        phase,
        [sample, partial, released, steady_a, steady_b],
        stable_tail_seconds=30.0,
    )
    assert summary["first_tracked_release_s"] == 20.0
    assert summary["first_all_tracked_released_s"] == 35.0
    assert summary["tracked_resident_start"] == 2
    assert summary["tracked_resident_end"] == 0
    assert summary["stable_tail_rss_median_mb"] == 0.25
    assert summary["stable_tail_cpu_avg"] == 0.375
    assert summary["post_release_stable_rss_mb"] == 0.25
    assert summary["rss_reclaimed_mb"] == 0.12
    assert release_expectation(summary) == "PASS"
'''
replace_once(old_self_test, new_self_test)

# Give the full preset enough post-release observation for a real 30s tail.
replace_once("        warm_inactive=225,\n        cold_inactive=70,\n", "        warm_inactive=230,\n        cold_inactive=75,\n")
replace_once("        hidden_warm=325,\n        hidden_cold=175,\n", "        hidden_warm=340,\n        hidden_cold=190,\n")

PATH.write_text(text, encoding="utf-8")

readme = README.read_text(encoding="utf-8")
readme = readme.replace(
    "  --interval 2 \\\n  --session stage5e-full\n",
    "  --interval 2 \\\n  --tail-seconds 30 \\\n  --session stage5e-full\n",
)
readme = readme.replace(
    "The full preset takes roughly 18–20 minutes depending on Slot load waits and sampling overhead.\n",
    "The full preset takes roughly 19–21 minutes depending on Slot load waits and sampling overhead. The final 30 seconds of each phase are reported separately as the stable tail, and release phases also report pre-release RSS, post-release stable RSS, and reclaimed memory.\n",
)
if "Stable-tail metrics" not in readme:
    readme = readme.replace(
        "Phase and runtime transitions are written as events so resource drops can be matched to the exact lifecycle transition instead of inferred from Activity Monitor.\n",
        "Phase and runtime transitions are written as events so resource drops can be matched to the exact lifecycle transition instead of inferred from Activity Monitor.\n\n### Stable-tail metrics\n\n`lifecycle-summary.json` and `lifecycle-report.md` separate whole-phase load/switch spikes from the final steady-state window. They include stable-tail RSS/CPU, first/all release timestamps, RSS immediately before the first release, post-release stable RSS/CPU, reclaimed RSS, and how long the run observed the fully released state. Override the default window with `--tail-seconds`.\n",
    )
README.write_text(readme, encoding="utf-8")
