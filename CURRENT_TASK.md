# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.8-001`
**Title:** Publish v0.5.8 and enter runtime observation
**Status:** `WAITING / RUNTIME OBSERVATION`
**Mode:** `OBSERVE`
**Task class:** `RELEASE / DOCUMENTATION / OBSERVATION`
**Authorized baseline:** `main@73eee804cbe32a32bd2cc15f957ee8b52e66e1253`
**Published release:** `v0.5.8`
**Published build:** `26`
**Release merge commit:** `36c8c1733f25095e5b1b2e0ba6d090a50aa22918`
**Historical runtime root cause:** `UNKNOWN`

## Release disposition

The v0.5.8 release is complete and verified.

Observed publication evidence:

- release preparation PR #154: `MERGED`;
- release PR head: `0f739221c9ea6938e43e9081d6d91483c4c8dee3`;
- release PR macOS CI run `40433884424` / #1152: `SUCCESS`;
- release PR QA DMG run `40433884389` / #545: `SUCCESS`;
- release merge commit: `36c8c1733f25095e5b1b2e0ba6d090a50aa22918`;
- Publish Release run `40434662992` / #38: `SUCCESS`;
- GitHub Release `v0.5.8`: public, non-draft, non-prerelease;
- tag `v0.5.8` points directly to `36c8c1733f25095e5b1b2e0ba6d090a50aa22918`;
- all four expected DMG/checksum/dSYM assets are present.

The release preparation changed documentation/control state and app version metadata only. It did not add a new runtime/product semantic change beyond the diagnostics implementation already merged in PR #153.

## Accepted product/runtime basis

The accepted runtime diagnostics production semantics remain:

`b6d9e6841da92033dbc2f5fbd5c325915e1e3864`

PR #153 delivered incident-oriented diagnostics covering shared incident correlation, bounded automatic snapshots, WebContent termination/recovery correlation, memory-pressure decision evidence, Attention abnormal-path evidence, previous-app restore terminal outcomes, page-app evidence corrections and redundant-log reduction without reducing health-probe cadence.

The historical WebContent stall/termination root cause is still `UNKNOWN`. The release does not claim a causal runtime fix.

## Observation authority

The active work is now observation only.

Authorized actions:

1. use FloatTabs v0.5.8 normally;
2. preserve/export Runtime Diagnostics when a fresh incident occurs;
3. record approximate incident time and affected Slot/site;
4. inspect and correlate diagnostic evidence read-only;
5. use normal recovery actions when needed after evidence preservation is practical;
6. report whether reload/reset/restart recovered the symptom as recovery evidence only.

No code, runtime policy, persistence, Browser Profile/session, focus, Attention business state, timeout, recovery or user-data mutation is authorized under observation mode.

## Incident capture guidance

For a fresh slowdown, stall, WebContent termination, Attention abnormality, or focus-restore anomaly, preserve when practical:

```text
APP_VERSION=v0.5.8
BUILD=26
APPROX_INCIDENT_TIME=<local time>
AFFECTED_SLOT=<slot/site>
SYMPTOM=<short description>
PRECEDING_ACTION=<what happened immediately before>
DIAGNOSTICS=<export/preserved runtime diagnostics>
RECOVERY_ACTION=<none/reload/reset/restart/etc>
RECOVERY_RESULT=<recovered/not recovered/unknown>
```

Do not treat recovery success as root-cause proof.

## Safety boundaries

Observation must preserve:

```text
RECOVERY_POLICY=UNCHANGED
RELOAD_RESET_BEHAVIOR=UNCHANGED
RESIDENCY_POLICY=UNCHANGED
ATTENTION_BUSINESS_STATE=UNCHANGED
FOCUS_POLICY=UNCHANGED
TIMEOUT_THRESHOLDS=UNCHANGED
BROWSER_PROFILES=UNCHANGED
WEBSITE_SESSIONS_DATA=UNCHANGED
PERSISTENCE=UNCHANGED
USER_DATA=UNTOUCHED
```

No Browser Profile, website session, cookie, preference, backup or persisted website data may be cleared merely to simplify diagnosis.

## Next engineering gate

If a real incident produces evidence suggesting a code/runtime change, stop at diagnosis and reconcile task authority before mutation.

A future fix must distinguish:

- observed symptom;
- recovery boundary;
- evidence-supported failure class;
- proven root cause, if any.

Until evidence proves otherwise:

`ROOT_CAUSE=UNKNOWN`
