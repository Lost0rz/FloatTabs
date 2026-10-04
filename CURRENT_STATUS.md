# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before implementation.

Machine-specific worktree paths are local evidence only and must not be committed.

## Mode

**MODE: DIAGNOSTIC-PROBE-CONSTRUCTION**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

The production worktree must be clean and exactly synchronized with freshly fetched `origin/main` before creating the next isolated construction worktree.

## Governance state

FT-GOV-002 is **CLOSED**.

PR #103 is MERGED and established the three-file control plane plus the corrected PR-context required-check rule.

## FT-DIAG-001 audit state

FT-DIAG-001 is **CLOSED — CONSTRUCTION_GATE_READY**.

Audit baseline:

`68d03a0991be4ed1569b41816628b62b0a3677a1`

Authoritative audit product:

`docs/diagnostics/FT-DIAG-001-architecture-audit.md`

The audit does **not** claim a root cause.

**STUCK-SLOT ROOT CAUSE: UNKNOWN**

The audit concluded that the next probe placement is sufficiently determined even though the incident cause is not.

### Final architectural conclusion

The diagnostic gap is not general log volume. It is missing cross-owner correlation across:

`session → source/build → Slot → physical WKWebView → navigation generation → document epoch → incident capture`

The highest-value missing boundary evidence is:

- exact source/build provenance;
- physical WebView identity;
- navigation generation/ticket identity;
- ordinary normal-state WebView attachment/hierarchy;
- bounded native → WebContent JavaScript responsiveness;
- bounded ChatGPT app/document health at explicit incident capture;
- exact identity on content-termination/rebuild evidence.

### Existing strengths to preserve

- Slot lifecycle delayed-work tokens;
- WebViewPool physical-object stale guards;
- ChatGPT Attention document token/epoch admission;
- ChatGPT Response document-token/WebView validation;
- Fullscreen restore generation and hierarchy checks;
- RuntimeDiagnostics non-authority/privacy model.

### Important current blind spot

The ChatGPT Attention liveness probe uses `evaluateJavaScript` without a timeout. A non-returning WebContent/JavaScript callback can leave the probe suspended without producing an explicit unresponsive classification.

This is an observation gap, not proof that such a hang is the current root cause.

## Boundary verdict

Current classifications:

| Boundary | Audit result |
| --- | --- |
| Persisted state → restored active Slot | PARTIALLY_OBSERVED |
| User selection → active Slot ID | OBSERVED |
| Active Slot → physical pool WebView | PARTIALLY_OBSERVED |
| Pool WebView → visible normal container | UNOBSERVED |
| Navigation → provisional/commit/finish/fail | PARTIALLY_OBSERVED |
| UI process → WebContent | PARTIALLY_OBSERVED |
| WebContent → admitted document | PARTIALLY_OBSERVED |
| Document → ChatGPT app health | PARTIALLY_OBSERVED |
| Document/WebKit → actual rendered pixels | UNOBSERVED / DEFERRED |
| OS network path → WebKit resource behavior | UNOBSERVED / DEFERRED |
| Content termination → recovery | OBSERVED, weak cross-identity correlation |
| Fullscreen source restore hierarchy | OBSERVED |

## Historical incident interpretation

Preserved runtime evidence supports only bounded conclusions:

- restart recovery is recovery evidence;
- per-Slot replacement recovery is recovery evidence;
- one post-commit stall had responsive JavaScript and later navigation finish;
- navigation finish can coexist with a visibly unhealthy ChatGPT page;
- WebContent terminations have separately occurred;
- network/resource errors have appeared, but no network/resource mechanism is established as the root cause.

No abandoned #99/#100/#101 behavior is production authority.

## Current task

**FT-DIAG-002 — Boundary Probe Foundation**

Construction is authorized only within the exact scope in `CURRENT_TASK.md` and the P0 section of the FT-DIAG-001 audit.

This is an **observation-only diagnostic construction task**.

## Explicitly not authorized

Do not implement in FT-DIAG-002:

- automatic recovery or reload escalation;
- manual per-Slot reset/replacement;
- hard replacement after probe timeout;
- periodic health sampling;
- broad DOM/error logging;
- request interception;
- private WebKit APIs;
- cache/cookie/site-data reset;
- screenshot/image persistence;
- automatic render snapshots;
- network-path monitoring;
- #102 changes.

## Open unrelated work

PR #102 remains **ACTIVE / OPEN / Draft**, separate MemoX durable-outbox work. FT-DIAG-002 must not modify it.

## Historical archive

Archive tags preserved by FT-GOV-002 remain historical evidence only. The `v0.2.6` provenance discrepancy remains non-blocking and outside FT-DIAG-002.
