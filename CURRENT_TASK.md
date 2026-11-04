# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-CHATGPT-URL-RESTORE-002`  
**Title:** ChatGPT hibernated-runtime fresh-URL restore — bounded mechanism corrective  
**Status:** **AUTHORIZED / LOCAL IMPLEMENTATION PENDING**  
**Task class:** `RESTORE-MECHANISM CORRECTIVE`  
**Baseline observed:** `main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Existing branch:** `codex/adaptive-lifecycle-wp2-policy`  
**Existing PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authorization and prior-stage reconciliation

The user authorized a **mechanism-first, no-preliminary-performance-spike** change on 2026-11-04, after a focused read-only audit of `WebViewPool`, Slot URL persistence, navigation observer, lifecycle coordinator, WP1 presentation, and existing tests.

This is a separate bounded restoration slice **within the same overarching Adaptive Lifecycle + Restore task**, not WP2 policy mutation, WP3 scheduling, or WP4 integration. Reuse the existing compatible branch/PR only after local checkout, clean/unique-work, and overlapping-writer safety checks. Do not create another physical worktree or PR as routine handoff overhead. Unknown competing writes or materially changed ref/authority: STOP.

The prior WP2 policy implementation, machine/CI evidence and short-run user smoke stay recorded, but its normal-use field-observation/final-closeout decision is **paused/superseded as the immediate execution stage**. Previous observations do not constitute acceptance of this new restore behavior. PR #195 remains Draft, not merge/release ready.

`docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md` still governs the unchanged WP2 lifecycle policy. `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md` remains the WP1 presentation/readiness regression authority. This card expressly authorizes the narrow new ChatGPT restore mechanism without revising V7's WP2-only policy scope.

## Frozen product decision

For an **already resident** Runtime, preserve same-instance fast reuse without reload or new navigation.

For a **hibernated/nonresident** Runtime whose actual **restore navigation target URL** is a supported ChatGPT URL per `ChatGPTSitePolicy.isSupportedChatGPTURL`, create a fresh `WKWebView` with the existing exact Browser Profile data store, and load `profile.currentURL ?? profile.homeURL` using existing `.useProtocolCachePolicy`. Do **not** apply an opaque `interactionState` snapshot to the new ChatGPT WebView. Clear any stale in-memory restore snapshot for that Slot. When hibernating a currently identified ChatGPT page, avoid capturing unnecessary `interactionState` and still perform the existing teardown safely.

All other sites retain current interaction-state restore/fallback behavior. Classification is based on a trusted supported URL, never Slot display name or blanket WebKit changes. Preserve exact conversation URL/path/query and existing WebAppURL safety checks; do not replace with ChatGPT homepage or synthesize message requests.

ChatGPT itself owns message retrieval/pagination. No API interception, arbitrary message limit, new cache cap, local message copy, DOM mutation, preload worker, or additional UI/Settings option. Skipping old interaction state may lose unsubmitted draft, scroll position, and WebKit back/forward entries; this tradeoff is acknowledged for a **hibernated** ChatGPT Runtime only. Never erase Browser Profile/site/session/configuration data.

## Authorized implementation scope

- `FloatTabs/Web/WebViewPool.swift`: narrow hibernate and fresh-create restore branch behavior; preserve existing single-owner runtime identity, observer/bridge teardown, exact Browser Profile and URL/cache policy.
- `FloatTabsTests/WebViewPoolTests.swift`: focused new/updated regressions for ChatGPT fresh URL restore, zero stale interaction-state application, memory-only snapshot discard, warm reuse, correct conversation URL, profile isolation, non-ChatGPT unchanged behavior, and existing lifecycle/ready/failure guards.
- `CURRENT_STATUS.md` / `CURRENT_TASK.md`: truthful control updates only if the verified execution outcome materially changes their semantics.
- An additional file needs prior bounded scope reconciliation, except for minimal adjacent test repair strictly required by the changed API.

No mutation to `SlotLifecycleCoordinator`, `PanelController`, `WebViewFactory`, `TabStore`, `SlotNavigationObserver`, ChatGPT response/attention DOM scripts, site-data/cache cleanup, UI, or notification routing by default.

## Execution and verification Gates

1. **Preflight**: obtain fresh `origin/main`, current PR head, control files, existing task branch and local checkout/worktree cleanliness/ownership; confirm no competing unique work or conflicting task authority. STOP on unsafe overlap.
2. **Implement smallest conditional**: no new lifecycle writer and no unneeded additional navigation. Preserve existing error/diagnostic semantics and correct Runtime identity.
3. **Focused tests**: prove ChatGPT hibernate -> fresh URL load exactly once (including deep conversation URL), no interaction-state apply, no stale snapshot retained; same-instance warm reuse, other-site restoration, explicit release behavior, custom Browser Profile and sibling isolation remain correct; run affected WebViewPool/WP1/lifecycle coverage.
4. **Consolidated machine closeout**: full XCTest, Debug/Release arm64, architecture/package-lock checks and exact-head required self-hosted CI + QA DMG where applicable; no new performance benchmark or prolonged pre-change experiment is required.
5. **Review and user experience**: bounded exact-diff data-safety review, then user-owned real Mac spot acceptance (warm switch, cold exact conversation reopen, other-site unaffected, login intact). `HUMAN_UI_ACCEPTANCE=PENDING` until explicit user verdict.
6. **Delivery**: commit/push only the authorized PR branch, verify remote ref after push; preserve PR as **Draft / unmerged** and never publish a release automatically.

## STOP

STOP if: active ChatGPT is rebuilt on warm revisit; a new code path could clear cookies/site data; ChatGPT cold path navigates to homepage in place of a known safe conversation URL; stale snapshot could be reused; an existing non-ChatGPT restore path is modified unintentionally; exact Runtime readiness/notification/focus is bypassed; an overlapping local writer contains unknown unique work; required machine gate fails; or the proposed fix needs wider ownership changes. Report the exact blocker without substituting reload/reset/cache clearing.

## Expected local execution receipt

```text
CARD_ID=
TASK_ID=
GOVERNANCE_ROUTE=
SKILLS_USED=
START_IDENTITY=
FINAL_IDENTITY=
CHANGED_PATHS=
FOCUSED_TESTS=
FULL_XCTEST=
ARM64_BUILD=
CI=
QA_DMG=
DATA_SAFETY=
HUMAN_UI_ACCEPTANCE=PENDING|PASS|FAIL
LOCAL_COMMIT=
REMOTE_DELIVERY=
REMOTE_REF=
REMOTE_COMMIT=
PR_195=
CONTROL_ALIGNMENT=
BLOCKERS=
NEXT_SAFE_ACTION=
```
