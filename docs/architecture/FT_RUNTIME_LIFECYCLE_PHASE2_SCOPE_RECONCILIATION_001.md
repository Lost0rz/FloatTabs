# FloatTabs Phase 2 Scope Reconciliation 001

**Program / Task:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `2 — Ready / Unread Decoupling`  
**Status:** `ACCEPTED CORRECTIVE EVIDENCE`  
**Observed implementation baseline:** `8a369bf2f64aa307cbe2362747673bdd9214f99f`

## Trigger

The first Phase 2 construction attempt remained inside the frozen production scope and passed focused Phase 2 tests (`241 executed / 3 skipped / 0 failures`), but the full XCTest suite stopped with one failure in `FloatTabsTests/BrowserProfileDuplicateTests.swift`.

The failing test drives the source Slot through `Generating -> Ready`, duplicates it into another Browser Profile, and then asserts that the original source Runtime/Profile/Ready state is not disturbed by the duplication operation. The test additionally encoded the historical expectation that a Ready Slot is Attention-protected.

## Read-only reconciliation finding

The Browser Profile duplication behavior itself is not in conflict with Phase 2. The test correctly continues to require that duplication leaves the source WebView, Attention bridge, Browser Profile identity, transient Ready state, and both resident runtimes untouched by the duplication operation.

The single stale assertion is the historical Phase 1-era semantic expectation:

```swift
XCTAssertTrue(attention.isAttentionProtected(source.id))
```

Phase 2 explicitly changes that cross-domain semantic to:

```text
Generating -> Runtime-protected
Ready      -> not Runtime-protected
```

The adjacent `testProtectedSourceDuplicateDoesNotAskSwitchConfirmation` uses a **Generating** source Slot, so its protection premise remains valid and must remain unchanged.

## Corrective authorization

`FloatTabsTests/BrowserProfileDuplicateTests.swift` is added to the Phase 2 authorized **test-only** scope for the narrow purpose of aligning this stale cross-domain regression expectation with the already-frozen Ready / Unread semantic.

Permitted change in that file:

- rename the affected test only if needed for semantic accuracy;
- change the Ready protection assertion from protected to non-protected;
- preserve all Browser Profile duplication, source-runtime identity, transient Ready-state, and residency assertions that do not conflict with the Phase 2 semantic.

This corrective does **not** authorize any Browser Profile production-code change, persistence/schema change, `SlotLifecycleCoordinator` change, `WebViewPool` change, detector/bridge change, unread-store change, timer/policy change, Phase 3/4 work, or release change.

## Verification continuation

After the narrow test correction, resume the existing Phase 2 verification sequence from the failed full-XCTest gate:

1. run the affected BrowserProfileDuplicate test/file;
2. rerun focused Phase 2 tests if the implementation changed after the prior focused run;
3. rerun full XCTest;
4. only after full XCTest passes, run Debug arm64 build, Release arm64 build, bounded real-runtime smoke, scope audit, implementation PR, exact-head required CI, independent web audit, and user-owned UI acceptance as already frozen.

No new product implementation is authorized by this reconciliation.
