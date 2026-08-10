# FloatTabs — Stage 5 Resource Benchmark Protocol

> Status: Stage 5 benchmark closeout baseline; final resource-lifecycle tuning validated on PR #10
> Base: `main` after Stage 5 Residency Policy merge (`f74500246e30514a3fd1ddb89ed5c64a903da575`)
> Scope: measurement and tuning only; no change to accepted Hot / Warm / Cold semantics without separate evidence and review.

## 1. Goal

Stage 5 functional Residency behavior is already accepted. This follow-up measures the real resource cost of the accepted policies on a Real Mac so future defaults, warnings, or timing changes are data-driven.

This PR must answer:

1. What is the incremental resource cost of 1 / 3 / 6 resident Slots?
2. How much does Hot cost relative to Warm when inactive?
3. How much memory is actually recovered by Cold after its 30-second grace period?
4. Does inactive media or site polling create sustained CPU / Energy / Network activity?
5. What switch-latency benefit does Hot provide for state-heavy pages such as a long ChatGPT conversation?
6. Is any tuning justified for Hot-count warnings, Warm cache timing, or the Cold grace period?

## 2. Non-goals

This benchmark PR does not:

- redesign Hot / Warm / Cold;
- silently demote a user-selected Residency policy;
- add site-specific autoplay hacks;
- change Website Mode / Window Size / Zoom semantics;
- change navigation, login, session, upload, download, or WebContent recovery behavior;
- optimize based on CI-host measurements alone.

## 3. Measurement environment

Record before every benchmark pass:

- Mac model / SoC;
- RAM;
- macOS version;
- FloatTabs commit SHA;
- power source: AC or battery;
- display count and resolution;
- active VPN / proxy if relevant;
- whether Developer Tools / Instruments are attached;
- browser/site login state;
- Website Mode and Window Size for every test Slot.

Use one fixed Real-Mac environment for comparisons within a benchmark series.

## 4. Metrics

Capture both FloatTabs host and WebKit child-process behavior.

### Memory

- FloatTabs host RSS;
- total FloatTabs-responsible WebContent RSS;
- Networking / GPU helper RSS when attributable;
- total FloatTabs process-tree RSS;
- memory delta from baseline.

### CPU

- FloatTabs host CPU%;
- aggregate FloatTabs-responsible WebContent CPU%;
- idle average;
- p95 / peak within a capture window.

### Energy

The local harness attempts a best-effort `top` POWER proxy when the target macOS exposes a numeric POWER column. This is diagnostic only, not joules and not a release threshold.

For deeper energy analysis, use Instruments Energy Log / Activity Monitor Energy Impact after memory/CPU findings justify it.

### Network

The first local harness intentionally reports Network as `N/A` until process-level `nettop` attribution is validated on the target macOS version. Do not report a number that may mix unrelated Safari/WebKit traffic.

A later benchmark-tool increment may add validated network attribution.

### Switch latency

The first external harness intentionally reports switch latency as `N/A`. An external process sampler cannot reliably know when a state-heavy SPA is actually interactive. Trustworthy click-to-interactive latency requires a small app-side instrumentation seam.

Real-Mac qualitative Hot acceptance remains valid; quantitative latency instrumentation is follow-up measurement work.

## 5. Test matrix

Every core comparison uses the same Slot content and order.

### A. One Slot baseline

Run each policy independently:

- 1 Hot;
- 1 Warm;
- 1 Cold active;
- 1 Cold after >30 seconds inactive and eviction.

Purpose: establish host/runtime fixed cost and single-WebView cost.

### B. Three Slots

Run:

- 3 Hot;
- 3 Warm;
- 3 Cold after eviction;
- mixed: 1 Hot + 1 Warm + 1 Cold.

Purpose: estimate incremental resident-WebView cost and validate mixed-policy behavior.

### C. Six Slots

Run:

- 6 Hot;
- 6 Warm;
- 6 Cold after eviction;
- mixed representative set: 2 Hot + 2 Warm + 2 Cold.

Purpose: identify whether scaling remains acceptable for the intended small, high-frequency Web App set.

## 6. Workloads

Use two workload classes.

### Controlled workload

Use stable pages with no intentional media playback to measure FloatTabs/WebKit residency overhead with minimal site noise.

### Representative real-site workload

Use the current priority compatibility set, with at least:

- ChatGPT: long conversation / state-heavy SPA;
- YouTube Desktop: video page;
- YouTube Mobile: same account/content class where possible;
- Bilibili Desktop: video page.

Real-site numbers must be labelled as observational because site scripts, ads, recommendations, polling, login state and CDN behavior vary over time.

## 7. State checkpoints

For every configuration capture these checkpoints after the system reaches steady state:

```text
S0  App launched, before test Slots are activated
S1  All required Slots activated once
S2  Active Slot idle
S3  Non-active resident Slots idle
S4  FloatTabs panel hidden
S5  Cold Slots inactive >30 s and evicted
S6  First return to each policy
S7  Repeated switch loop
```

The benchmark must not assume a configured Hot Slot has a live WebView before it has been activated in the current app process.

## 8. Repetition

For future latency comparisons:

- discard the first warm-up switch where appropriate;
- run at least 10 repeated switches;
- report median;
- report p95 when sample count is sufficient;
- record obvious outliers separately rather than silently deleting them.

For memory / idle CPU / Energy:

- use repeated fixed observation windows;
- use the same sites and same app state for paired Hot/Warm/Cold comparisons;
- repeat suspicious results before tuning product behavior.

## 9. Required result tables

### Residency scaling

| Slots | Policy | Host RSS | WebContent RSS | Total RSS | Idle CPU | Energy | Network idle |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Hot | | | | | | |
| 1 | Warm | | | | | | |
| 1 | Cold evicted | | | | | | |
| 3 | Hot | | | | | | |
| 3 | Warm | | | | | | |
| 3 | Cold evicted | | | | | | |
| 6 | Hot | | | | | | |
| 6 | Warm | | | | | | |
| 6 | Cold evicted | | | | | | |

### Switch latency

| Workload | From | To | Median | p95 | Notes |
|---|---|---|---:|---:|---|
| ChatGPT long conversation | Warm/other | Hot ChatGPT | | | qualitative accepted; quantitative instrumentation pending |
| ChatGPT long conversation | other | Warm ChatGPT | | | instrumentation pending |
| Controlled page | other | Hot | | | instrumentation pending |
| Controlled page | other | Warm | | | instrumentation pending |
| Controlled page | other | Cold evicted | | | instrumentation pending |

## 10. Decision rules

Measurements may justify a follow-up change only if the evidence is repeatable and the product trade-off is explicit.

Potential outcomes:

- keep or tune current defaults based on repeatable Real-Mac evidence;
- add a non-blocking warning when many Hot Slots are selected;
- tune the Cold grace period;
- improve inactive scheduling without changing user-visible Residency semantics;
- identify a FloatTabs-owned sustained CPU/network defect and fix it in a separate focused commit/PR section.

Do not infer a FloatTabs defect solely from a real site's own background polling or media policy.

## 11. Closeout criteria

This benchmark PR is complete when:

- 1 / 3 / 6 Slot matrices are recorded on a Real Mac;
- Hot / Warm / Cold memory deltas are quantified;
- hidden-app idle CPU / Energy behavior is measured;
- representative network-idle behavior is either measured with validated attribution or explicitly deferred with rationale;
- Hot vs Warm switch latency is measured once trustworthy app-side instrumentation exists;
- Cold recreation latency and recovered memory are measured;
- any recommended tuning is separated into evidence-backed changes;
- Stage 5 product semantics remain unchanged unless a specific measured problem warrants a separately reviewed adjustment.

## 12. Local benchmark harness

The repository includes:

```text
tools/benchmark/floattabs_benchmark.py
```

It uses only Python standard library + built-in macOS commands.

### 12.1 What it automatically does

- finds the running `FloatTabs` host process;
- reads `~/Library/Application Support/FloatTabs/WebAppProfiles.json` for Slot policy/rendering metadata;
- asks for `sudo -v` once so `/bin/launchctl procinfo` can attribute WebKit helpers to the exact FloatTabs host;
- excludes unrelated Safari/other-app WebKit processes;
- samples host/WebContent/Networking/GPU RSS and CPU;
- writes raw CSV samples;
- writes JSON summaries;
- writes one Markdown report with Hot vs Warm memory premium, Cold memory recovery, WebContent process-count changes and hidden-idle CPU diagnostics;
- records unavailable/unvalidated metrics as `N/A` instead of fabricating values.

### 12.2 Quick prerequisite check

```bash
python3 tools/benchmark/floattabs_benchmark.py doctor --sudo
```

This validates FloatTabs PID discovery, profile loading and responsible WebKit process attribution.

### 12.3 Recommended guided run

With FloatTabs already built and running:

```bash
python3 tools/benchmark/floattabs_benchmark.py guided --slots 3
```

The tool shows current Slots and lets the tester choose which Slot numbers are included. It then guides:

```text
Hot
→ 15 s capture
Warm
→ 15 s capture
Warm + panel hidden
→ 15 s capture
Cold
→ automatic 35 s eviction wait
→ 15 s capture
→ report.md
```

For every policy stage, the tester changes settings through the real FloatTabs context menu. The harness never edits profile JSON directly. It re-reads the JSON and verifies that requested policy/media values were persisted before recording.

For Cold, the first selected Slot remains Active while the other selected Slots are eligible for eviction. Therefore a three-Slot guided run measures two inactive Cold evictions in the final checkpoint. Add a separate control Slot in a later full matrix if all three targets must be evicted simultaneously.

### 12.4 Ad-hoc capture

To add one named checkpoint to a session:

```bash
python3 tools/benchmark/floattabs_benchmark.py capture warm-3 \
  --session my-run \
  --policy warm \
  --state steady \
  --slots 3 \
  --seconds 20
```

Regenerate an existing session report:

```bash
python3 tools/benchmark/floattabs_benchmark.py report .benchmark-results/my-run
```

### 12.5 Output

Default output root:

```text
.benchmark-results/
└── session-YYYYMMDD-HHMMSS/
    ├── session.json
    ├── report.md
    └── captures/
        ├── hot.csv
        ├── hot.summary.json
        ├── warm.csv
        ├── warm.summary.json
        ├── warm-hidden.csv
        ├── warm-hidden.summary.json
        ├── cold.csv
        └── cold.summary.json
```

`.benchmark-results/` is gitignored.

### 12.6 Automated interpretation heuristics

The report labels Hot memory premium relative to physical RAM as:

```text
< 2% RAM   Low
2–5% RAM   Moderate
> 5% RAM   High
```

Hidden aggregate CPU diagnostic:

```text
≤ 1%       Good
1–3%       Watch
> 3%       Investigate
```

These are diagnostic heuristics, not product/release thresholds. They exist to make the first local report easy to read without requiring manual arithmetic. Any tuning still requires repeatable Real-Mac evidence.

## 12. Automated Real-Mac control channel

PR #10 adds a Debug-only loopback benchmark control channel. The Python harness must use this channel for automated policy transitions instead of editing `WebAppProfiles.json` directly.

Properties:

- compiled/started only under `DEBUG`;
- binds to `127.0.0.1` on an ephemeral port;
- publishes PID/port plus a random per-process token in `~/Library/Application Support/FloatTabs/BenchmarkControl.json` with user-only file permissions;
- mutates Residency/media only through `TabStore.updateResourcePolicy`;
- activates Slots only through `TabStore.select`;
- hides/shows only through `PanelController` product paths;
- Release behavior is unchanged.

### Cold timing correctness

An automatic Cold measurement requires at least one unselected control Slot.

For each selected test Slot the harness:

```text
configure selected Slots = Cold
→ activate every selected Slot once
→ activate one unselected control Slot
→ NOW every selected test Slot is inactive
→ start authoritative Cold inactivity timer
→ optional short Cold-pending capture
→ wait >30 s from final control activation
→ Cold-evicted capture
```

The harness must not treat a selected Slot that remains Active as Cold-eligible. The report records the exact count of inactive selected Slots and uses that count for per-Slot reclaimed-memory estimates.

### Automatic first-pass sequence

```text
Hot visible
→ Hot hidden
→ Warm visible
→ Warm hidden
→ Cold pending
→ Cold evicted
→ restore original selected-Slot Residency/media
→ restore original active Slot
→ restore original panel visibility
```

Use:

```bash
python3 tools/benchmark/floattabs_benchmark.py auto --slots 2
```

`guided` remains only as a legacy/manual fallback.
