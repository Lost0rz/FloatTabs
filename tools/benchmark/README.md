# FloatTabs Benchmark Runbook

This directory contains two macOS-only benchmark tools:

- `floattabs_benchmark.py` — short steady-state Hot/Warm/Cold comparison.
- `floattabs_lifecycle_benchmark.py` — continuous long-cycle Active/Hot/Warm/Cold timeline.

Both tools use only the Python standard library plus macOS built-in process tools. The long-cycle runner talks to the Debug FloatTabs benchmark control channel and restores changed Slot policy / active Slot / panel visibility on exit.

## 1. Build and launch the current Debug app

```bash
cd ~/Documents/Code/FloatTabs

pkill -x FloatTabs 2>/dev/null || true
rm -rf .derivedData

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

open .derivedData/Build/Products/Debug/FloatTabs.app
```

Use only one running FloatTabs process for clean attribution.

## 2. Check benchmark prerequisites

```bash
python3 tools/benchmark/floattabs_benchmark.py doctor --sudo
```

The tool may ask for the macOS administrator password once because `launchctl procinfo` is used to attribute WebKit helper processes to the current FloatTabs host process.

## 3. Long-cycle lifecycle benchmark

Recommended acceptance run:

```bash
python3 tools/benchmark/floattabs_lifecycle_benchmark.py run \
  --preset full \
  --slots 2 \
  --interval 2 \
  --tail-seconds 30 \
  --session stage5e-full
```

Keep at least one extra configured Slot unselected; it is used as the inactive control Slot.

The tool prompts for the test Slots, then automatically runs:

1. baseline visible sampling;
2. Hot Active;
3. Hot inactive;
4. Warm Active;
5. Warm inactive past the 120s Warm TTL;
6. Cold Active;
7. Cold inactive past the 30s Cold grace;
8. Hot selected + panel hidden;
9. Warm selected + panel hidden past 120s hidden grace + 120s Warm TTL;
10. Cold selected + panel hidden past 120s hidden grace + 30s Cold grace.

The full preset takes roughly 19–21 minutes depending on Slot load waits and sampling overhead. The final 30 seconds of each phase are reported separately as the stable tail, and release phases also report pre-release RSS, post-release stable RSS, and reclaimed memory.

For a harness plumbing check only:

```bash
python3 tools/benchmark/floattabs_lifecycle_benchmark.py run \
  --preset quick \
  --slots 2 \
  --session stage5e-quick
```

`quick` intentionally does not cross every production timer and must not be used to judge Warm lifecycle behavior.

## 4. Long-cycle outputs

Results are written under:

```text
.benchmark-results/<session>/
```

Important files:

```text
lifecycle-timeline.csv
lifecycle-events.json
lifecycle-summary.json
lifecycle-report.md
lifecycle-chart.html
session.json
```

Open the curve report with:

```bash
open .benchmark-results/stage5e-full/lifecycle-chart.html
```

The continuous timeline records:

- FloatTabs host RSS / CPU;
- attributed WebContent / Networking / GPU RSS and CPU;
- total process-tree RSS / CPU;
- WebContent/helper process counts;
- actual `resident_slot_count` from `WebViewPool`;
- tracked live Slot count;
- pending Cold/Warm release counts;
- media-protected Slot count;
- hidden-active grace state;
- active Slot and panel visibility.

Phase and runtime transitions are written as events so resource drops can be matched to the exact lifecycle transition instead of inferred from Activity Monitor.

### Stable-tail metrics

`lifecycle-summary.json` and `lifecycle-report.md` separate whole-phase load/switch spikes from the final steady-state window. They include stable-tail RSS/CPU, first/all release timestamps, RSS immediately before the first release, post-release stable RSS/CPU, reclaimed RSS, and how long the run observed the fully released state. Override the default window with `--tail-seconds`.

## 5. Baseline policy

The long-cycle baseline forces selected test Slots to `Pause When Inactive` while each Residency policy is measured. This intentionally isolates Hot/Warm/Cold lifecycle behavior from video decode, audio playback and site-specific background activity.

`Allow Background Audio` protection should be measured as a separate media scenario after the residency baseline is accepted.

## 6. Self-tests

```bash
python3 -m py_compile tools/benchmark/floattabs_benchmark.py
python3 -m py_compile tools/benchmark/floattabs_lifecycle_benchmark.py
python3 tools/benchmark/floattabs_benchmark.py --self-test
python3 tools/benchmark/floattabs_lifecycle_benchmark.py --self-test
```
