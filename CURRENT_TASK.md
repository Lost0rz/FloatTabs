# FloatTabs Current Task

**Task ID:** FT-DIAG-003
**Title:** Fresh Incident Classification & Read-Only App-Layer Evidence
**Status:** ACTIVE — `INCIDENT_CAPTURED_APP_LAYER_EVIDENCE_REQUIRED`

## Objective

Preserve the fresh stuck-Tab incident and perform one bounded read-only evidence pass that can distinguish page-application/bootstrap failure, request/resource failure, and a possible inactive-finish/warm-reuse lifecycle interaction.

This task does **not** authorize a fix, a recovery experiment, a rebuild, or new diagnostic code.

## Incident binding

Only evidence that can be tied to the accepted incident identity is authoritative for this pass:

- session `7C81B78D-F98A-496F-A2E6-94E3DE74194A`;
- Slot `89953BED-613F-4E31-AAEC-C8D71B5956B3`;
- WKWebView `28A7FDCA-1263-4AE1-B242-7459C5DF692F`;
- runtime generation `4`;
- navigation generation `1`;
- source revision `1897fae15031673a37800ac57758e462d8dfb851`;
- incident snapshots `75B3A768-F766-40B4-97BC-8A0F416C0B2F` and `B35360B0-11A3-4719-AA5C-C9AEC37F0AEC`.

Remote comparison confirms the later `a77f9a4e1f6e9aba897ccfa8afb20c702e37d711` control-plane transition changed only `CURRENT_STATUS.md` and `CURRENT_TASK.md`. Do not rebuild the live incident solely to eliminate this governance-only provenance difference.

## Confirmed starting classification

`CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER`

At capture, navigation was finished, renderer JavaScript was responsive, the current WebView/Slot ownership and geometry were coherent, the document was complete and visible, and the ChatGPT shell existed while the composer did not.

This classification is not root cause evidence.

## Hypotheses under test

- **H1:** ChatGPT page bootstrap/hydration/application state failed or remained incomplete.
- **H2:** a required network/service/script/resource/API dependency failed, was blocked, timed out, or became pathologically slow.
- **H3:** navigation completing while inactive and later warm reuse contributed to a lifecycle race or missed page transition.

## Authorized evidence pass

Before touching the incident, refresh remote refs and read the three control-plane files. Then:

- verify the running process and current diagnostics still refer to the accepted incident identity;
- preserve/export the existing diagnostics before any further inspection;
- determine whether an already available, read-only page inspection surface can observe the current document without restart/reload/configuration change;
- if available, capture only bounded metadata relevant to application exceptions/rejections and failed/blocked/timed-out required resources or requests, with timestamps and current-document identity;
- preserve any existing console/network/inspector artifact without request/response bodies, credentials, cookies, tokens, prompts, or assistant content;
- make no source, test, build, preference, website-data, or control-plane changes locally.

One bounded pass is enough. Repeated poking of a live incident is not authorized.

## Decision matrix

| Same-incident evidence | Classification result | Next state |
| --- | --- | --- |
| JavaScript exception or unhandled rejection tied to bootstrap/app initialization | H1 supported; record the exact bounded error class/timestamp | STOP and seal for remote review |
| Required script/chunk/resource/fetch/XHR fails, is blocked, times out, or returns an error status | H1/H2 supported; record dependency class/status/timestamp without sensitive payloads | STOP and seal for remote review |
| No page/request failure is visible, but this incident retains the inactive-finish/warm-reuse sequence | H3 remains a hypothesis only; one incident is insufficient for causality | STOP and seal; remote side decides whether a future controlled recurrence test is justified |
| Renderer probe fails/times out or the WebContent process terminates before recovery | Current failure class changes toward renderer/content-process failure | STOP immediately and seal |
| Slot/WKWebView/runtime/navigation/document identity changes, or any navigation/reload occurs | Same-incident causal binding is lost | STOP immediately and seal |
| Required page-layer evidence is unavailable without mutation/relaunch/rebuild/configuration change | `CURRENT_INCIDENT_PAGE_EVIDENCE_UNAVAILABLE_WITHOUT_MUTATION` | STOP and seal; next task may authorize a bounded probe enhancement |
| Available page-layer evidence is clean or inconclusive after one bounded pass | Root cause remains unknown | STOP and seal; no speculative fix |

## Mandatory STOP and evidence sealing

Stop immediately when any decision-matrix row becomes true, when the symptom recovers/disappears, or before any step that would alter the current document/runtime.

Evidence sealing means:

- preserve the latest diagnostic export plus any bounded inspector/console/network artifact already obtained;
- record local timestamp, visible symptom, Slot and runtime identities, and the exact last action taken;
- perform no reload/Home/back/forward/new navigation, restart, quit, rebuild, reinstall, WebView replacement, cache/cookie/site-data reset, or configuration toggle before remote review.

If operational recovery is unavoidable, seal first when possible, then record the exact recovery action and result separately. Recovery success is not root-cause evidence.

## Prohibited

Do not modify production source, tests, diagnostics, lifecycle/recovery behavior, website data, or PR #102. Do not add a new probe during this task. Do not manufacture repeated incidents.

## Completion gate

FT-DIAG-003 leaves this state only after one of the following is returned for independent remote review:

1. decisive same-incident page-layer evidence;
2. a sealed inconclusive bounded pass;
3. `CURRENT_INCIDENT_PAGE_EVIDENCE_UNAVAILABLE_WITHOUT_MUTATION`;
4. an identity change/recovery that invalidates further same-incident capture.

The web-side control plane will then decide whether the next task is additional bounded diagnostics, a controlled recurrence experiment, or an evidence-backed fix.
