# FloatTabs Phase 7 Real-Mac Acceptance Runbook

Phase 7 current product semantics are **Automatic / Keep Loaded**.

The historical Stage 5E Hot/Warm/Cold lifecycle acceptance path is retired. `floattabs_lifecycle_benchmark.py` now exits with a retirement notice and must not be used as Phase 7 evidence. Historical implementation remains available in Git history only.

Current entry points:

- `floattabs_phase7_acceptance.py` — Phase 7 Real-Mac lifecycle acceptance;
- `floattabs_benchmark.py` — low-level process attribution, doctor utilities and ChatGPT observer-effect diagnostics. Its historical Hot/Warm/Cold comparison modes are not Phase 7 acceptance.

## 1. Required source identity

Run acceptance only from the exact PR head intended for review. The harness records:

- Git branch and SHA;
- macOS / hardware information;
- selected Slot IDs;
- original Runtime Retention / media settings;
- FloatTabs host PID.

The checkout must be clean for final evidence.

## 2. Build the Debug app from the acceptance head

The Real-Mac harness uses the Debug-only loopback benchmark control channel. QA DMG validates packaging and manual product behavior, but the DMG does not expose this debug control channel.

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

Use exactly one running FloatTabs process.

## 3. Preflight

Precise aggregate WebKit process attribution uses `launchctl procinfo` and may request the administrator password once:

```bash
python3 tools/benchmark/floattabs_benchmark.py doctor --sudo
```

Prepare at least **three real ChatGPT Slots**. The main run will temporarily set the selected A/B/C Slots to `Automatic` + `Pause When Inactive` where needed and restores their original settings afterward.

Before starting:

- A/B/C must not already be generating;
- leave WebKit fullscreen;
- do not use reload/reset/restart to make a scenario pass;
- do not clear cookies, site data or Browser Profiles.

## 4. Main Phase 7 run

```bash
python3 tools/benchmark/floattabs_phase7_acceptance.py run \
  --session phase7-real-mac-final
```

The harness prompts for A/B/C when Slot IDs are not supplied explicitly.

It covers:

1. **3 Automatic Slots / normal budget / grace convergence**
   - load A → B → C;
   - verify the normal Automatic budget converges through deterministic LRU;
   - after the 30-second inactivity grace, verify only the active Automatic Slot remains among A/B/C;
   - record aggregate FloatTabs/WebKit RSS/helper PID evidence before/after reclaim.

2. **Rapid A → B → A**
   - machine-check final active/resident Slot A;
   - ask the user to confirm there is no persistent wrong-Slot attachment or wrong page.

3. **Background generation protection**
   - user starts a sufficiently long ChatGPT response in B;
   - B becomes inactive;
   - verify B remains resident past the Automatic grace while generation is active;
   - after generation completes, verify B becomes reclaimable normally.

4. **Keep Loaded ordinary inactivity**
   - Keep Loaded A is activated, then left inactive while C is active;
   - verify A survives ordinary inactivity past the Automatic grace without a hidden Hot presentation path.

5. **Reclaim → Phase 6 restore → session continuity**
   - reclaim Automatic A;
   - select A again and verify Runtime materializes;
   - user confirms Browser Profile/login/session/page continuity without reset/reload.

### Optional development-only flags

```text
--slot-id <UUID>       pass exactly three times to avoid the interactive Slot picker
--skip-generation      skips the generation scenario; final result becomes incomplete
--no-sudo              skips precise responsible-PID attribution
--allow-dirty          development only; never use for final evidence
```

## 5. Keep Loaded relaunch check

The main run restores original Slot settings, then reports `PENDING_RELAUNCH`. The non-preload requirement is verified separately so the harness never silently restarts the app.

Prepare:

```bash
python3 tools/benchmark/floattabs_phase7_acceptance.py prepare-relaunch \
  --session phase7-real-mac-final
```

Then:

1. quit FloatTabs normally;
2. relaunch the **same Debug build from the same checkout**;
3. do not select the prepared Keep Loaded test Slot A;
4. verify:

```bash
python3 tools/benchmark/floattabs_phase7_acceptance.py verify-relaunch \
  --session phase7-real-mac-final
```

PASS requires:

- the Keep Loaded preference persisted;
- the inactive Keep Loaded Slot was **not proactively materialized solely because of the preference**.

If the relaunch sequence is interrupted, restore the saved A/B/C configuration with:

```bash
python3 tools/benchmark/floattabs_phase7_acceptance.py restore \
  --session phase7-real-mac-final
```

## 6. Evidence outputs

Results are written to:

```text
.benchmark-results/<session>/
```

Expected files:

```text
session.json
lifecycle-timeline.csv
lifecycle-events.json
lifecycle-summary.json
lifecycle-report.md
lifecycle-chart.html
acceptance-result.json
relaunch-check.json        # after prepare-relaunch
```

`acceptance-result.json` distinguishes:

- machine-observed Runtime resident-set facts;
- aggregate process/RSS supporting evidence;
- user-observed visual/session continuity;
- the separate Keep Loaded relaunch result.

## 7. Evidence boundary

The harness intentionally does **not** claim exact per-Slot WebContent memory or PID attribution. Public WebKit evidence does not support that claim reliably.

Allowed interpretation:

```text
product resident_slot_ids / active_slot_id
+ aggregate FloatTabs-responsible WebKit helper PID/RSS trends
+ user-visible session continuity
→ bounded Real-Mac lifecycle evidence
```

Do not infer exact Slot memory from helper RSS alone.

## 8. Warning / critical pressure

Phase 7 machine tests cover:

```text
warning Automatic target = 1
critical Automatic target = 0
critical ordering may reclaim inactive unprotected Keep Loaded after Automatic
```

The current Debug control channel does not expose a safe explicit memory-pressure injection action. The Real-Mac harness therefore **does not manufacture real system memory pressure**. The accepted Phase 7 contract explicitly allows critical-pressure Keep Loaded ordering to be proven deterministically through tests instead.

## 9. QA DMG / human UI acceptance

Real-Mac lifecycle evidence uses the Debug build. Separately, the same final acceptance head must pass required macOS CI and QA DMG. After the harness passes, use the QA DMG for final product-facing checks such as:

- Runtime Retention UI shows only Automatic / Keep Loaded;
- no Hot/Warm/Cold current controls remain;
- ordinary switching/focus remains usable;
- login/session behavior remains intact.

QA DMG success alone is not lifecycle acceptance.

## 10. Self-tests

```bash
python3 -m py_compile tools/benchmark/floattabs_benchmark.py
python3 -m py_compile tools/benchmark/floattabs_phase7_acceptance.py
python3 -m py_compile tools/benchmark/floattabs_lifecycle_benchmark.py

python3 tools/benchmark/floattabs_benchmark.py --self-test
python3 tools/benchmark/floattabs_phase7_acceptance.py --self-test
```

The retired Stage 5E script intentionally exits non-zero when invoked.
