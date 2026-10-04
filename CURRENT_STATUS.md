# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual branch/PR heads. Refresh refs before local execution.

Machine-specific worktree paths remain local-only.

## Mode

**MODE: QA-INCIDENT-EVIDENCE**

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`  
**PRODUCTION_BRANCH:** `main`  
**EXPECTED_UPSTREAM:** `origin/main`

For source changes or a future QA build, the local production checkout must be CLEAN and exactly equal freshly fetched `origin/main`.

The currently captured incident is a preserved evidence exception to the ordinary rebuild-to-latest rule: do not rebuild, reinstall, reload, navigate, reset, or replace the running WebView merely to make its provenance equal the later control-plane-only main commit while same-incident evidence may still exist.

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

FT-DIAG-002 adds observation-only diagnostic capability for build/source provenance, physical WKWebView identity, navigation/runtime correlation, stall classification, bounded renderer probing, explicit stuck-tab capture, bounded ChatGPT DOM health, and termination/rebuild correlation.

It does not establish a root cause and does not implement a stuck-tab fix.

## FT-DIAG-003

**FT-DIAG-003 — Fresh Incident Classification & Read-Only App-Layer Evidence**

**STATUS: ACTIVE — INCIDENT_CAPTURED_APP_LAYER_EVIDENCE_REQUIRED**

### Accepted incident identity

The fresh incident export is internally coherent and is accepted for classification with this identity:

- session: `7C81B78D-F98A-496F-A2E6-94E3DE74194A`;
- Slot: `89953BED-613F-4E31-AAEC-C8D71B5956B3`;
- WKWebView: `28A7FDCA-1263-4AE1-B242-7459C5DF692F`;
- runtime generation: `4`;
- navigation generation: `1`;
- source revision: `1897fae15031673a37800ac57758e462d8dfb851`;
- source tree state: `clean`;
- source revision exact: `true`;
- build channel: `Debug`;
- QA label: `ft-diag-002-qa`;
- accepted incident snapshots: `75B3A768-F766-40B4-97BC-8A0F416C0B2F` and `B35360B0-11A3-4719-AA5C-C9AEC37F0AEC`.

The live main had advanced from `1897fae15031673a37800ac57758e462d8dfb851` to `a77f9a4e1f6e9aba897ccfa8afb20c702e37d711` before this classification. Remote comparison confirms that single intervening commit changed only `CURRENT_STATUS.md` and `CURRENT_TASK.md`; no production/runtime source changed. This governance-only drift does not invalidate the already captured runtime evidence, but it must not be generalized to future builds.

### Confirmed facts

The incident supports the following facts, not a causal root cause:

- top-level navigation reached `finished`; at capture `is_loading=false`, progress was 1.0, and the navigation callback was current;
- the renderer answered two bounded JavaScript probes successfully in approximately 16.6 ms and 9.1 ms;
- both probes reported `document.readyState=complete` and a visible document;
- the physical WKWebView was resident, visible, non-zero-sized, attached under the expected host, matched the pool/presented/source ownership, and matched the active Slot;
- the ChatGPT health probe succeeded twice, five seconds apart;
- both health probes found a conversation shell but no composer;
- the loading marker existed in the DOM but was not visibly rendered; no bounded conversation-error element was detected; ChatGPT generation state was idle;
- the Slot was deactivated after navigation commit but before navigation finished; that navigation finished while the Slot was inactive; the same warm WKWebView was later reused before the incident capture;
- nearby fresh ChatGPT navigations in the same session were also slow, but the export does not identify a specific request, response, script, API, or network failure.

**INCIDENT FAILURE CLASS:** `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`

This is an observation/classification label only.

**STUCK-SLOT ROOT CAUSE: UNKNOWN**

The current evidence rules out, for this capture state, a renderer hang, wrong/absent presented WebView, zero/hidden WebView geometry, active-Slot mismatch, stale navigation callback, and an unfinished top-level navigation as the immediate explanation for the visible symptom.

### Hypotheses still requiring evidence

1. **H1 — ChatGPT application bootstrap/state initialization failure.** A script/chunk/API/session bootstrap failure, application exception, rejected promise, hydration/state transition failure, or equivalent page-layer dependency may have left the shell present without a composer.
2. **H2 — Network/service/resource failure or extreme latency.** The broader slow-navigation cluster is consistent with this category, but current incident evidence contains no request-level proof.
3. **H3 — inactive-finish / warm-reuse lifecycle interaction.** Deactivation-before-finish followed by warm reuse is a confirmed temporal sequence; causality is not established from one incident.

No specific HTTP error, JavaScript exception, OpenAI service failure, or FloatTabs lifecycle defect is currently confirmed.

### Evidence gate

The next authorized activity is a **bounded, read-only same-incident evidence capture**. It may inspect already available page/renderer diagnostic surfaces only if doing so does not reload, navigate, restart, rebuild, reinstall, replace the WebView, clear data, or change runtime configuration.

Target evidence is metadata sufficient to discriminate H1/H2/H3, such as an already available same-document JavaScript exception/rejection or failed/blocked/timed-out application dependency. Do not capture page bodies, cookies, auth headers, tokens, prompts, responses, or unrelated browsing content.

If the required page-layer evidence is not already accessible without mutating the live incident, stop and record that diagnostic gap. That result is sufficient to define a later bounded diagnostic-probe task; it is not permission to add probes during FT-DIAG-003.

## Runtime construction state

**NEW RUNTIME FIX CONSTRUCTION: NOT AUTHORIZED**

**NEW DIAGNOSTIC CONSTRUCTION: NOT AUTHORIZED DURING THIS LIVE INCIDENT**

Do not add recovery behavior or infer a fix from the current classification. A new construction task requires either decisive same-incident evidence or a confirmed evidence gap after the current incident is sealed.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify it as part of FT-DIAG-003.

## Historical evidence

PRs #99–#101 remain abandoned historical experiments only.

Historical stall/process/network incidents are useful comparison evidence but must not be merged into this incident's causal chain without matching runtime/document identity.
