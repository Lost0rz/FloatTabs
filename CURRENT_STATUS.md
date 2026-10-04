# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: QA-RUNTIME-OBSERVATION**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

Before any QA build or runtime check, the local production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

The live `origin/main` after the control-plane transition is the accepted QA source baseline. Do not hard-code an older SHA when verifying the installed/running application.

## FT-DIAG-001

FT-DIAG-001 is **CLOSED — CONSTRUCTION_GATE_READY**.

Authoritative audit:

`docs/diagnostics/FT-DIAG-001-architecture-audit.md`

The audit concluded that the diagnostic problem was missing cross-owner identity and boundary evidence, not insufficient log volume.

## FT-DIAG-002

FT-DIAG-002 is **CLOSED — MERGED / REMOTE_AUDIT_PASS**.

PR #106 was merged after:
- full local validation;
- exact-head PR-context required CI PASS;
- final remote code audit PASS.

Merge-produced main commit for #106:

`e706809800ccc63c1562bd6b09319fa7f600c522`

FT-DIAG-002 adds observation-only diagnostic capability:
- build/source provenance;
- physical WKWebView runtime identity;
- navigation generation/ticket correlation;
- provisional/post-commit stall classification;
- bounded renderer/JavaScript probe;
- explicit QA stuck-tab snapshot;
- bounded ChatGPT app-health snapshot;
- termination/rebuild correlation.

It does **not** establish a root cause and does **not** implement a stuck-tab fix.

**STUCK-SLOT ROOT CAUSE: UNKNOWN**

## Current task

**FT-DIAG-003 — QA Runtime Baseline & Fresh Incident Observation**

The next authorized activity is local QA baseline verification followed by ordinary real-world use until a fresh incident occurs.

The required running QA application must be built from a CLEAN checkout exactly equal to current `origin/main` and must report:
- `source_tree_state = clean`;
- `source_revision_exact = true`;
- `source_revision = accepted origin/main SHA`;
- DEBUG QA capability available for explicit stuck-tab capture.

If the currently installed/running app does not satisfy that identity, it is not an accepted observation build.

## Fresh incident rule

When the stuck/blank/black symptom occurs:

1. do not Reload/Home/restart/reset first;
2. use **Capture Stuck Tab Snapshot (QA)**;
3. preserve the returned incident ID and current diagnostics;
4. export recent diagnostics;
5. return the evidence for classification before any recovery experiment.

Recovery success must continue to be recorded separately from causal classification.

## Runtime construction state

**NEW RUNTIME FIX CONSTRUCTION: NOT AUTHORIZED**

Do not add recovery logic, reset logic, new probes, or further diagnostics unless the fresh incident evidence identifies a specific remaining gap and a new task authorizes it.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify it as part of FT-DIAG-003.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only.

The historical `v0.2.6` tag provenance discrepancy remains non-blocking and outside FT-DIAG-003.
