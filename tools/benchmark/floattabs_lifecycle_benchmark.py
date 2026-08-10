#!/usr/bin/env python3
"""Long-cycle Real-Mac lifecycle benchmark for FloatTabs.

This companion to ``floattabs_benchmark.py`` records one continuous timeline
across Active -> inactive -> eviction and hidden-panel transitions.  It uses the
Debug benchmark control channel and the same responsible-PID WebKit attribution
as the short benchmark harness.

Outputs per session:
- lifecycle-timeline.csv       every process/runtime sample
- lifecycle-events.json        phase starts + runtime state transitions
- lifecycle-summary.json       per-phase summaries and detected release times
- lifecycle-report.md          compact interpretation
- lifecycle-chart.html         dependency-free RSS / CPU / resident curves

The tool restores changed Slot policies, active Slot and panel visibility on exit.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import floattabs_benchmark as core

PRODUCT_COLD_GRACE_SECONDS = 30
PRODUCT_WARM_TTL_SECONDS = 180
PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS = 120
DEFAULT_INTERVAL = 2.0


@dataclass(frozen=True)
class Preset:
    baseline: int
    active: int
    hot_inactive: int
    warm_inactive: int
    cold_inactive: int
    hidden_hot: int
    hidden_warm: int
    hidden_cold: int

    @property
    def duration(self) -> int:
        return (
            self.baseline
            + self.active * 3
            + self.hot_inactive
            + self.warm_inactive
            + self.cold_inactive
            + self.hidden_hot
            + self.hidden_warm
            + self.hidden_cold
        )


PRESETS: Dict[str, Preset] = {
    # Useful to validate the harness plumbing only; it intentionally does not
    # cross every production timer.
    "quick": Preset(
        baseline=8,
        active=8,
        hot_inactive=15,
        warm_inactive=25,
        cold_inactive=40,
        hidden_hot=15,
        hidden_warm=25,
        hidden_cold=40,
    ),
    # Crosses Cold and Warm inactive timers, but keeps hidden testing short.
    "standard": Preset(
        baseline=15,
        active=20,
        hot_inactive=60,
        warm_inactive=210,
        cold_inactive=60,
        hidden_hot=60,
        hidden_warm=0,
        hidden_cold=170,
    ),
    # Full production lifecycle: crosses 30s Cold, 120s hidden-active grace,
    # and 180s Warm TTL (120 + 180 for the hidden-selected Warm release).
    "full": Preset(
        baseline=20,
        active=25,
        hot_inactive=120,
        warm_inactive=225,
        cold_inactive=70,
        hidden_hot=160,
        hidden_warm=325,
        hidden_cold=175,
    ),
}


@dataclass(frozen=True)
class Phase:
    label: str
    policy: str
    state: str
    duration: int
    tracked_ids: Tuple[str, ...]


class TimelineRecorder:
    def __init__(
        self,
        *,
        session_dir: Path,
        host_pid: int,
        resolver: core.OwnershipResolver,
        client: core.BenchmarkControlClient,
        interval: float,
        session_start: float,
        warnings: Sequence[str],
    ) -> None:
        self.session_dir = session_dir
        self.host_pid = host_pid
        self.resolver = resolver
        self.client = client
        self.interval = interval
        self.session_start = session_start
        self.warnings = list(warnings)
        self.rows: List[Dict[str, object]] = []
        self.events: List[Dict[str, object]] = []
        self.phase_summaries: List[Dict[str, object]] = []
        self._last_runtime_signature: Optional[Tuple[object, ...]] = None

    def event(self, kind: str, phase: str, detail: str, **metadata: object) -> None:
        payload: Dict[str, object] = {
            "session_elapsed_s": round(time.monotonic() - self.session_start, 3),
            "captured_at": core.iso_now(),
            "kind": kind,
            "phase": phase,
            "detail": detail,
        }
        payload.update(metadata)
        self.events.append(payload)
        print(f"  EVENT {payload['session_elapsed_s']:>7.1f}s  {detail}", flush=True)

    def capture(self, phase: Phase) -> Dict[str, object]:
        if phase.duration <= 0:
            return {}
        print(f"\n=== {phase.label} · {phase.duration}s ===")
        self.event("phase_start", phase.label, f"start {phase.label}", policy=phase.policy, state=phase.state)
        phase_start = time.monotonic()
        phase_rows: List[Dict[str, object]] = []
        next_tick = phase_start
        self._last_runtime_signature = None

        while True:
            now = time.monotonic()
            phase_elapsed = now - phase_start
            if phase_elapsed >= phase.duration and phase_rows:
                break
            if now < next_tick:
                time.sleep(min(next_tick - now, 0.2))
                continue

            self.resolver.refresh(force=(not phase_rows))
            ownership = self.resolver.snapshot()
            metrics = core.ps_metrics([self.host_pid, *ownership.keys()])
            if self.host_pid not in metrics:
                raise RuntimeError("FloatTabs exited during lifecycle measurement.")
            process_sample = core.aggregate_sample(
                self.host_pid,
                ownership,
                metrics,
                time.monotonic() - self.session_start,
            )
            status = self.client.status()
            resident_ids = sorted(str(value) for value in (status.get("resident_slot_ids") or []))
            resident_set = set(resident_ids)
            tracked_resident_ids = sorted(slot_id for slot_id in phase.tracked_ids if slot_id in resident_set)
            media_protected = sorted(str(value) for value in (status.get("media_protected_slot_ids") or []))

            row: Dict[str, object] = {
                "captured_at": core.iso_now(),
                "session_elapsed_s": round(time.monotonic() - self.session_start, 3),
                "phase_elapsed_s": round(phase_elapsed, 3),
                "phase": phase.label,
                "policy": phase.policy,
                "state": phase.state,
                "panel_visible": bool(status.get("visible", False)),
                "active_slot_id": status.get("active_slot_id") or "",
                "resident_slot_count": int(status.get("resident_slot_count", len(resident_ids)) or 0),
                "tracked_resident_count": len(tracked_resident_ids),
                "tracked_slot_count": len(phase.tracked_ids),
                "pending_cold_release_count": int(status.get("pending_cold_release_count", 0) or 0),
                "pending_warm_release_count": int(status.get("pending_warm_release_count", 0) or 0),
                "media_protected_count": len(media_protected),
                "hidden_active_grace_pending": bool(status.get("hidden_active_grace_pending", False)),
                "tracked_resident_ids": ";".join(tracked_resident_ids),
                **{key: value for key, value in process_sample.items() if key != "elapsed_s"},
            }
            self.rows.append(row)
            phase_rows.append(row)

            signature = (
                row["panel_visible"],
                row["active_slot_id"],
                row["resident_slot_count"],
                row["tracked_resident_count"],
                row["pending_cold_release_count"],
                row["pending_warm_release_count"],
                row["media_protected_count"],
                row["hidden_active_grace_pending"],
            )
            if signature != self._last_runtime_signature:
                self.event(
                    "runtime_transition",
                    phase.label,
                    (
                        f"resident={row['resident_slot_count']} tracked={row['tracked_resident_count']}/"
                        f"{row['tracked_slot_count']} coldPending={row['pending_cold_release_count']} "
                        f"warmPending={row['pending_warm_release_count']} hiddenGrace={row['hidden_active_grace_pending']}"
                    ),
                    resident_slot_count=row["resident_slot_count"],
                    tracked_resident_count=row["tracked_resident_count"],
                    pending_cold_release_count=row["pending_cold_release_count"],
                    pending_warm_release_count=row["pending_warm_release_count"],
                    hidden_active_grace_pending=row["hidden_active_grace_pending"],
                )
                self._last_runtime_signature = signature

            print(
                f"  {float(row['session_elapsed_s']):7.1f}s  "
                f"RSS={core.human_mb(float(row['total_rss_kb'])):<10} "
                f"CPU={float(row['total_cpu']):6.2f}%  "
                f"resident={row['resident_slot_count']} tracked={row['tracked_resident_count']}/"
                f"{row['tracked_slot_count']}  WC={row['webcontent_count']}",
                flush=True,
            )
            next_tick += self.interval

        summary = summarize_phase(phase, phase_rows)
        self.phase_summaries.append(summary)
        self.event("phase_end", phase.label, f"end {phase.label}")
        self.flush()
        return summary

    def flush(self) -> None:
        write_timeline_csv(self.session_dir / "lifecycle-timeline.csv", self.rows)
        (self.session_dir / "lifecycle-events.json").write_text(
            json.dumps(self.events, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        summary_payload = {
            "generated_at": core.iso_now(),
            "warnings": self.warnings,
            "phases": self.phase_summaries,
        }
        (self.session_dir / "lifecycle-summary.json").write_text(
            json.dumps(summary_payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        write_markdown_report(self.session_dir, self.phase_summaries, self.events)
        write_html_chart(self.session_dir, self.rows, self.events)


def write_timeline_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def first_time(rows: Sequence[Dict[str, object]], predicate) -> Optional[float]:
    for row in rows:
        if predicate(row):
            return float(row.get("phase_elapsed_s", 0.0))
    return None


def summarize_phase(phase: Phase, rows: Sequence[Dict[str, object]]) -> Dict[str, object]:
    if not rows:
        return {"label": phase.label, "sample_count": 0}
    process_summary = core.summarize_samples(rows)
    first_all_released = first_time(rows, lambda row: int(row.get("tracked_resident_count", 0)) == 0)
    first_hidden_grace_end = first_time(rows, lambda row: not bool(row.get("hidden_active_grace_pending", False)))
    first_pending_clear = first_time(
        rows,
        lambda row: int(row.get("pending_cold_release_count", 0)) == 0
        and int(row.get("pending_warm_release_count", 0)) == 0,
    )
    start_rss = float(rows[0].get("total_rss_kb", 0.0))
    end_rss = float(rows[-1].get("total_rss_kb", 0.0))
    return {
        "label": phase.label,
        "policy": phase.policy,
        "state": phase.state,
        "duration_s": phase.duration,
        "sample_count": len(rows),
        "tracked_slot_count": len(phase.tracked_ids),
        "tracked_resident_start": int(rows[0].get("tracked_resident_count", 0)),
        "tracked_resident_end": int(rows[-1].get("tracked_resident_count", 0)),
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
    }


def release_expectation(summary: Dict[str, object]) -> str:
    label = str(summary.get("label", ""))
    released = summary.get("first_all_tracked_released_s")
    if label == "hot-inactive" or label == "hot-hidden":
        return "PASS" if released is None else "CHECK: Hot released"
    if label == "cold-inactive":
        return "PASS" if isinstance(released, (int, float)) and released >= PRODUCT_COLD_GRACE_SECONDS - 4 else "CHECK"
    if label == "warm-inactive":
        return "PASS" if isinstance(released, (int, float)) and released >= PRODUCT_WARM_TTL_SECONDS - 6 else "CHECK"
    if label == "cold-hidden":
        floor = PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS + PRODUCT_COLD_GRACE_SECONDS
        return "PASS" if isinstance(released, (int, float)) and released >= floor - 8 else "CHECK"
    if label == "warm-hidden":
        floor = PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS + PRODUCT_WARM_TTL_SECONDS
        return "PASS" if isinstance(released, (int, float)) and released >= floor - 10 else "CHECK"
    return "INFO"


def write_markdown_report(
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
        "| Phase | State | RSS start | RSS end | Δ RSS | Avg CPU | p95 CPU | Tracked resident | All released at | Check |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for item in summaries:
        released = item.get("first_all_tracked_released_s")
        released_text = f"{float(released):.1f}s" if isinstance(released, (int, float)) else "—"
        lines.append(
            f"| {item.get('label')} | {item.get('state')} | {float(item.get('total_rss_start_mb', 0)):.1f} MB | "
            f"{float(item.get('total_rss_end_mb', 0)):.1f} MB | {float(item.get('total_rss_delta_mb', 0)):+.1f} MB | "
            f"{float(item.get('total_cpu_avg', 0)):.2f}% | {float(item.get('total_cpu_p95', 0)):.2f}% | "
            f"{item.get('tracked_resident_start', 0)}→{item.get('tracked_resident_end', 0)} | {released_text} | {release_expectation(item)} |"
        )
    lines.extend([
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
        "- `lifecycle-summary.json`: machine-readable phase summaries.",
        "- `lifecycle-chart.html`: local interactive-free SVG curves for RSS, CPU and resident WebViews.",
        "",
        "Do not treat one noisy real-site run as a release threshold. Repeat an anomalous phase before changing lifecycle policy.",
        "",
    ])
    (session_dir / "lifecycle-report.md").write_text("\n".join(lines), encoding="utf-8")


def _svg_polyline(
    rows: Sequence[Dict[str, object]],
    *,
    key: str,
    width: int,
    height: int,
    padding: int,
) -> Tuple[str, float]:
    if not rows:
        return "", 0.0
    xs = [float(row.get("session_elapsed_s", 0.0)) for row in rows]
    ys = [float(row.get(key, 0.0)) for row in rows]
    x_max = max(max(xs), 1.0)
    y_max = max(max(ys), 1.0)
    drawable_w = max(width - padding * 2, 1)
    drawable_h = max(height - padding * 2, 1)
    points = []
    for x, y in zip(xs, ys):
        px = padding + x / x_max * drawable_w
        py = height - padding - y / y_max * drawable_h
        points.append(f"{px:.1f},{py:.1f}")
    return " ".join(points), y_max


def write_html_chart(
    session_dir: Path,
    rows: Sequence[Dict[str, object]],
    events: Sequence[Dict[str, object]],
) -> None:
    if not rows:
        return
    width, height, padding = 1200, 260, 44
    charts = [
        ("total_rss_kb", "Total RSS", "MB", 1.0 / 1024.0),
        ("total_cpu", "Aggregate CPU", "%", 1.0),
        ("tracked_resident_count", "Tracked live WKWebViews", "count", 1.0),
    ]
    max_time = max(float(row.get("session_elapsed_s", 0.0)) for row in rows) or 1.0
    phase_events = [event for event in events if event.get("kind") == "phase_start"]
    sections: List[str] = []
    for key, title, unit, scale in charts:
        scaled_rows = [dict(row, **{key: float(row.get(key, 0.0)) * scale}) for row in rows]
        points, ymax = _svg_polyline(scaled_rows, key=key, width=width, height=height, padding=padding)
        markers: List[str] = []
        for event in phase_events:
            elapsed = float(event.get("session_elapsed_s", 0.0))
            x = padding + elapsed / max_time * (width - padding * 2)
            label = html.escape(str(event.get("phase", "")))
            markers.append(
                f'<line x1="{x:.1f}" y1="{padding}" x2="{x:.1f}" y2="{height-padding}" class="phase" />'
                f'<text x="{x+3:.1f}" y="18" class="phase-label">{label}</text>'
            )
        sections.append(f"""
<section>
<h2>{html.escape(title)}</h2>
<div class="range">0 → {ymax:.1f} {html.escape(unit)}</div>
<svg viewBox="0 0 {width} {height}" role="img" aria-label="{html.escape(title)} over time">
  <line x1="{padding}" y1="{height-padding}" x2="{width-padding}" y2="{height-padding}" class="axis" />
  <line x1="{padding}" y1="{padding}" x2="{padding}" y2="{height-padding}" class="axis" />
  {''.join(markers)}
  <polyline points="{points}" class="series" />
</svg>
</section>
""")
    document = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>FloatTabs Lifecycle Benchmark</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; max-width: 1280px; }}
section {{ margin: 28px 0 42px; }}
svg {{ width: 100%; height: auto; border: 1px solid #bbb; }}
.series {{ fill: none; stroke: currentColor; stroke-width: 2; }}
.axis {{ stroke: #888; stroke-width: 1; }}
.phase {{ stroke: #aaa; stroke-width: 1; stroke-dasharray: 4 4; }}
.phase-label {{ font-size: 11px; fill: currentColor; }}
.range {{ margin-bottom: 6px; opacity: .7; }}
</style></head><body>
<h1>FloatTabs Long-Cycle Lifecycle Benchmark</h1>
<p>Continuous timeline. Vertical markers are phase transitions.</p>
{''.join(sections)}
</body></html>"""
    (session_dir / "lifecycle-chart.html").write_text(document, encoding="utf-8")


def estimated_runtime(preset: Preset, activation_wait: float, slots: int) -> float:
    # Three visible policies plus three hidden policy preparations each touch all
    # selected Slots. This deliberately overestimates slightly.
    activation_overhead = 6 * max(slots, 1) * max(activation_wait, 0.0)
    return preset.duration + activation_overhead


def configure_and_warm(
    client: core.BenchmarkControlClient,
    selected_ids: Sequence[str],
    selected_names: Sequence[str],
    policy: str,
    activation_wait: float,
) -> None:
    status = client.configure(selected_ids, policy, "pauseWhenInactive")
    core.verify_control_policy(status, selected_ids, policy)
    for slot_id, name in zip(selected_ids, selected_names):
        client.activate(slot_id)
        print(f"  activated {name}")
        if activation_wait > 0:
            time.sleep(activation_wait)


def run_mode(args: argparse.Namespace) -> int:
    core.ensure_macos()
    preset = PRESETS[args.preset]
    host_pid, warnings = core.choose_host_pid(args.pid)
    core.validate_sudo()
    resolver = core.OwnershipResolver(host_pid)
    resolver.refresh(force=True)
    client = core.BenchmarkControlClient(host_pid)
    initial_status = client.status()
    profiles = core.control_profiles(initial_status)
    if len(profiles) < 2:
        raise RuntimeError("Lifecycle benchmark needs at least two configured Slots.")

    persisted = core.all_profile_summaries()
    core.print_profiles(persisted)
    selected = core.prompt_selected_profiles(persisted, args.slots)
    selected_ids = [str(profile.get("id")) for profile in selected]
    selected_names = [str(profile.get("name")) for profile in selected]
    unselected = [profile for profile in profiles if str(profile.get("id")) not in selected_ids]
    if not unselected:
        raise RuntimeError("Leave at least one Slot unselected; it is used as the inactive control Slot.")

    original_by_id = {str(profile.get("id")): profile for profile in profiles}
    original_active = initial_status.get("active_slot_id")
    original_visible = bool(initial_status.get("visible", False))
    control = next(
        (profile for profile in unselected if str(profile.get("id")) == str(original_active)),
        unselected[0],
    )
    control_id = str(control.get("id"))
    control_name = str(control.get("name", "Control"))
    primary_id = selected_ids[0]

    session_dir = core.create_session(Path(args.results_root), args.session)
    meta_path = session_dir / "session.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta.update({
        "lifecycle_benchmark": True,
        "preset": args.preset,
        "selected_slots": selected,
        "control_slot": {"id": control_id, "name": control_name},
        "original_active_slot_id": original_active,
        "original_panel_visible": original_visible,
        "product_timers_s": {
            "cold_grace": PRODUCT_COLD_GRACE_SECONDS,
            "warm_ttl": PRODUCT_WARM_TTL_SECONDS,
            "hidden_active_grace": PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS,
        },
    })
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    estimate = estimated_runtime(preset, args.activation_wait, len(selected_ids))
    print("\n=== FloatTabs long-cycle benchmark ===")
    print("Tracked Slots: " + ", ".join(selected_names))
    print(f"Inactive control Slot: {control_name}")
    print(f"Preset: {args.preset}; expected sampling time ≈ {estimate / 60.0:.1f} minutes")
    print("Media policy is forced to Pause When Inactive for a clean Residency baseline.")
    print(f"Results: {session_dir}")

    session_start = time.monotonic()
    recorder = TimelineRecorder(
        session_dir=session_dir,
        host_pid=host_pid,
        resolver=resolver,
        client=client,
        interval=max(args.interval, 0.5),
        session_start=session_start,
        warnings=warnings,
    )

    def restore() -> None:
        print("\nRestoring original FloatTabs state...")
        for slot_id in selected_ids:
            original = original_by_id.get(slot_id) or {}
            try:
                client.configure_one(
                    slot_id,
                    str(original.get("residency", "warm")),
                    str(original.get("background_media", "pauseWhenInactive")),
                )
            except RuntimeError as exc:
                print(f"WARNING: restore policy failed for {slot_id}: {exc}")
        if original_active:
            try:
                client.activate(str(original_active))
            except RuntimeError as exc:
                print(f"WARNING: restore active Slot failed: {exc}")
        try:
            client.show() if original_visible else client.hide()
        except RuntimeError as exc:
            print(f"WARNING: restore visibility failed: {exc}")

    try:
        client.show()
        recorder.capture(Phase("baseline", "baseline", "visible", preset.baseline, tuple(selected_ids)))

        for policy, inactive_seconds in (
            ("hot", preset.hot_inactive),
            ("warm", preset.warm_inactive),
            ("cold", preset.cold_inactive),
        ):
            print(f"\nPreparing {policy.upper()} visible cycle...")
            configure_and_warm(client, selected_ids, selected_names, policy, args.activation_wait)
            client.activate(primary_id)
            recorder.capture(Phase(f"{policy}-active", policy, "active", preset.active, (primary_id,)))
            client.activate(control_id)
            recorder.capture(Phase(f"{policy}-inactive", policy, "inactive", inactive_seconds, tuple(selected_ids)))

        for policy, duration in (
            ("hot", preset.hidden_hot),
            ("warm", preset.hidden_warm),
            ("cold", preset.hidden_cold),
        ):
            if duration <= 0:
                continue
            print(f"\nPreparing {policy.upper()} hidden-selected cycle...")
            client.show()
            configure_and_warm(client, selected_ids, selected_names, policy, args.activation_wait)
            client.activate(primary_id)
            client.hide()
            recorder.capture(Phase(f"{policy}-hidden", policy, "hidden-selected", duration, tuple(selected_ids)))
            client.show()
    finally:
        recorder.flush()
        restore()

    print("\n=== Long-cycle benchmark complete ===")
    print(f"Markdown: {session_dir / 'lifecycle-report.md'}")
    print(f"Curves:   {session_dir / 'lifecycle-chart.html'}")
    print(f"CSV:      {session_dir / 'lifecycle-timeline.csv'}")
    print("Open the curve report with:")
    print(f"  open {json.dumps(str(session_dir / 'lifecycle-chart.html'))}")
    return 0


def self_test_mode() -> int:
    assert PRESETS["full"].warm_inactive > PRODUCT_WARM_TTL_SECONDS
    assert PRESETS["full"].cold_inactive > PRODUCT_COLD_GRACE_SECONDS
    assert PRESETS["full"].hidden_warm > PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS + PRODUCT_WARM_TTL_SECONDS
    assert PRESETS["full"].hidden_cold > PRODUCT_HIDDEN_ACTIVE_GRACE_SECONDS + PRODUCT_COLD_GRACE_SECONDS

    phase = Phase("cold-inactive", "cold", "inactive", 60, ("a", "b"))
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
    assert estimated_runtime(PRESETS["full"], 1.0, 2) > PRESETS["full"].duration
    print("FloatTabs lifecycle benchmark self-test: PASS")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Record a continuous FloatTabs Active/Hot/Warm/Cold lifecycle resource timeline."
    )
    parser.add_argument("--self-test", action="store_true", help="Run pure-Python lifecycle harness tests and exit.")
    subparsers = parser.add_subparsers(dest="command")
    run = subparsers.add_parser("run", help="Run the automated long-cycle benchmark on the current Debug app.")
    run.add_argument("--preset", choices=sorted(PRESETS), default="full")
    run.add_argument("--slots", type=int, default=2, help="Number of test Slots; keep at least one extra Slot as control.")
    run.add_argument("--interval", type=float, default=DEFAULT_INTERVAL, help="Sampling interval in seconds.")
    run.add_argument("--activation-wait", type=float, default=1.5, help="Load settle time after each automatic Slot activation.")
    run.add_argument("--session", default=None, help="Optional results session name.")
    run.add_argument("--results-root", default=str(core.DEFAULT_RESULTS_ROOT))
    run.add_argument("--pid", type=int, default=None)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.self_test:
            return self_test_mode()
        if args.command == "run":
            return run_mode(args)
        parser.print_help()
        return 2
    except KeyboardInterrupt:
        print("\nLifecycle benchmark cancelled. Partial CSV/report were preserved.", file=sys.stderr)
        return 130
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
