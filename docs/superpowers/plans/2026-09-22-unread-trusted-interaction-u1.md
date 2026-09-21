# Trusted Page Interaction Acknowledgement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Acknowledge an unread ChatGPT response only after a validated trusted manual scroll or pointerdown inside an assistant response presentation, including when the FloatTabs window is physically visible but not key, while preserving strict completion and explicit-selection semantics.

**Architecture:** Keep \`AttentionPresentation.Facts\` as the only presentation authority and add a pure \`isInteractionSurfacePresented(_ facts: Facts)\` predicate that omits the key-window requirement only for trusted page interaction. Extend the existing version-3 response content-world channel with a fixed \`trustedInteraction/assistantPointer\` event, validate it in \`ChatGPTResponseBridge\`, forward it through \`WebViewPool\`, and let \`PanelController\` use the existing unread coordinator authority. Manual scroll remains a separate speech callback and uses the same new interaction-surface gate.

**Tech Stack:** Swift, AppKit, WebKit, WKContentWorld JavaScript, XCTest, xcodebuild.

**Spec:** User-provided frozen Phase U1 — Trusted Page Interaction Acknowledgement specification attached to this task.

## Global Constraints

- Base must be exact \`main\` / \`0e1a03830a9bdc95da4fa88d8bb4dfff0763397d\`.
- Branch must be \`fix/unread-trusted-interaction-u1\`; PR title must be \`fix: acknowledge unread on trusted page interaction\`.
- PR remains Draft, Open, and Unmerged; do not mark ready or merge.
- Do not modify \`ChatGPTAttentionBridge.swift\`, \`ChatGPTUnreadResponseCoordinator.swift\`, \`UnreadResponseStore.swift\`, or \`Package.resolved\`.
- Do not change completion visibility semantics, attention semantics, detector behavior, response identity, persistence ownership, or explicit-selection retry semantics.
- No polling, \`setInterval\`, completion watchdog, background heartbeat, timer resync, or app-wake resync; these are U2.
- No response-owned unread, response-ID persistence, generation sequence authority, \`acknowledgedResponseID\`, or late-finish dedupe; these are U3.
- Trusted pointer messages contain only \`version\`, \`event\`, \`documentToken\`, and fixed \`interactionKind\`.
- Privacy sanitizer remains strict; no button text, aria label, response content, DOM path, HTML, URL, clipboard, or selection text may enter diagnostics or the message protocol.
- \`event.isTrusted\` is the script admission gate; synthetic events and programmatic clicks must not acknowledge.
- \`onSpeechManualScroll\` and programmatic speech-follow guards retain their existing behavior.

## Review Focus

- A physically visible normal WebView with \`webPresentationOwnsActiveInteraction == false\` must be an interaction surface for trusted input but must remain not user-visible for completion and attention decisions; covered by \`AttentionPresentation\` predicate tests and hover-scroll integration.
- A pointer target inside an assistant toolbar/copy button must classify structurally, while sidebar/composer/model/settings controls must not classify; covered by the DEBUG-only DOM fixture and script-contract tests.
- A valid trusted interaction from a resident non-current WebView must not clear its Slot; covered by the inactive-hot-WebView integration test.
- Old document, wrong WebView, non-main-frame, unsupported-origin, and non-HTTP(S) messages must be dropped before any PanelController acknowledgement attempt; covered by bridge validation tests and cross-feature stale/invalid tests.
- Completion-time strict visibility and explicit-selection retry must remain unchanged after \`UnreadPresentationFacts\` grows; covered by existing regression groups run unchanged plus explicit assertions in cross-feature tests.

---

### Task 1: Add the pure interaction-surface presentation predicate

**Files:**
- Modify: \`FloatTabs/Panel/AttentionPresentation.swift\`
- Test: \`FloatTabsTests/WebAttentionPresentationTests.swift\`

**Interfaces:**
- Consumes: existing \`AttentionPresentation.Facts\`.
- Produces: \`AttentionPresentation.isInteractionSurfacePresented(_ facts: Facts) -> Bool\`.

- [ ] **Step 1: Write the failing pure predicate tests**

Add focused tests for these exact truth tables:

\`\`\`swift
func testInteractionSurfaceNormalPresentationDoesNotRequireKeyWindow() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        pooledWebViewExists: true,
        normalCurrentWebViewIsSlotWebView: true,
        sourceWindowIsVisible: true
    )

    XCTAssertTrue(AttentionPresentation.isInteractionSurfacePresented(facts))
    XCTAssertFalse(AttentionPresentation.isUserVisible(facts))
}

func testInteractionSurfaceRejectsNonCurrentHotWebView() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        pooledWebViewExists: true,
        sourceWindowIsVisible: true
    )
    XCTAssertFalse(AttentionPresentation.isInteractionSurfacePresented(facts))
}

func testInteractionSurfaceRejectsHiddenNormalSource() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        pooledWebViewExists: true,
        normalCurrentWebViewIsSlotWebView: true
    )
    XCTAssertFalse(AttentionPresentation.isInteractionSurfacePresented(facts))
}

func testInteractionSurfaceRejectsMissingPooledWebView() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        normalCurrentWebViewIsSlotWebView: true,
        sourceWindowIsVisible: true
    )
    XCTAssertFalse(AttentionPresentation.isInteractionSurfacePresented(facts))
}

func testInteractionSurfaceAcceptsFullscreenSourceWithoutKeyWindow() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        sessionIsLocked: true,
        fullscreenSourceSlotID: slotA
    )
    XCTAssertTrue(AttentionPresentation.isInteractionSurfacePresented(facts))
}

func testInteractionSurfaceAcceptsVisibleFullscreenCompanionWithoutKeyWindow() {
    let facts = AttentionPresentation.Facts(
        slotID: slotA,
        sessionIsLocked: true,
        panelIsVisible: true,
        companionSlotID: slotA,
        companionCurrentWebViewIsSlotWebView: true
    )
    XCTAssertTrue(AttentionPresentation.isInteractionSurfacePresented(facts))
}

func testInteractionSurfaceRejectsHiddenOrWrongFullscreenCompanion() {
    let hidden = AttentionPresentation.Facts(
        slotID: slotA,
        sessionIsLocked: true,
        panelIsVisible: false,
        companionSlotID: slotA,
        companionCurrentWebViewIsSlotWebView: true
    )
    let wrongSlot = AttentionPresentation.Facts(
        slotID: slotA,
        sessionIsLocked: true,
        panelIsVisible: true,
        companionSlotID: slotB,
        companionCurrentWebViewIsSlotWebView: true
    )
    XCTAssertFalse(AttentionPresentation.isInteractionSurfacePresented(hidden))
    XCTAssertFalse(AttentionPresentation.isInteractionSurfacePresented(wrongSlot))
}
\`\`\`

The tests must also assert that \`isUserVisible\` remains false for the physically visible, non-key normal facts and that the existing fullscreen predicates still retain their active-interaction requirement.

- [ ] **Step 2: Run the presentation tests and verify RED**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -only-testing:FloatTabsTests/WebAttentionPresentationTests
\`\`\`

Expected: compile failure because \`isInteractionSurfacePresented\` does not yet exist.

- [ ] **Step 3: Implement the minimal pure predicate**

Add only this decision to \`AttentionPresentation\`:

\`\`\`swift
static func isInteractionSurfacePresented(_ facts: Facts) -> Bool {
    if facts.sessionIsLocked {
        return facts.fullscreenSourceSlotID == facts.slotID
            || (facts.panelIsVisible
                && facts.companionSlotID == facts.slotID
                && facts.companionCurrentWebViewIsSlotWebView)
    }
    return facts.pooledWebViewExists
        && facts.normalCurrentWebViewIsSlotWebView
        && facts.sourceWindowIsVisible
}
\`\`\`

The locked branches must require only the U1 facts specified by the contract: matching fullscreen source, or locked + visible panel + matching companion + current companion WebView. Do not alter \`isUserVisible\`, \`isNormalPresentation\`, \`isFullscreenSource\`, or \`isCompanion\`.

- [ ] **Step 4: Run the presentation tests and verify GREEN**

Run the same command. Expected: all presentation tests pass, including the pre-existing strict attention tests.

- [ ] **Step 5: Commit**

\`\`\`bash
git add FloatTabs/Panel/AttentionPresentation.swift FloatTabsTests/WebAttentionPresentationTests.swift
git commit -m "feat: add trusted interaction surface predicate"
\`\`\`

### Task 2: Add structural assistant-pointer admission in the content-world script

**Files:**
- Modify: \`FloatTabs/Web/ChatGPTResponseExtraction.swift\`
- Test: \`FloatTabsTests/ChatGPTResponseExtractionTests.swift\`
- Test: \`FloatTabsTests/ChatGPTResponseBridgeTests.swift\`

**Interfaces:**
- Consumes: existing \`assistantRoots()\` structure and version-3 message channel.
- Produces: \`ChatGPTTrustedPageInteractionKind.assistantPointer\` and a version-3 \`trustedInteraction\` message with no content-bearing fields.

- [ ] **Step 1: Write failing script-contract and DOM fixture tests**

Add tests asserting the script contains capture-phase \`pointerdown\`, an explicit \`if (!event.isTrusted) return;\` gate, the assistant structural selectors, and the fixed protocol field names, while not containing content/label/path fields. Add a DEBUG-only page fixture with an assistant conversation turn containing an action toolbar/copy button plus separate composer and sidebar buttons. Evaluate the DEBUG-only classifier hook against selectors and assert assistant targets classify as \`assistantPointer\` while composer/sidebar targets classify as nil. Also assert a synthetic \`dispatchEvent(new PointerEvent('pointerdown'))\` does not emit a native trusted-interaction callback.

- [ ] **Step 2: Run extraction/bridge tests and verify RED**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -only-testing:FloatTabsTests/ChatGPTResponseExtractionTests -only-testing:FloatTabsTests/ChatGPTResponseBridgeTests
\`\`\`

Expected: the new classifier/protocol assertions fail because no assistant-pointer event exists.

- [ ] **Step 3: Implement the fixed interaction kind and structural classifier**

Add a fixed enum:

\`\`\`swift
enum ChatGPTTrustedPageInteractionKind: String, Equatable, Sendable {
    case manualScroll
    case assistantPointer
}
\`\`\`

In the existing content-world script, add one structural ancestor classifier that first recognizes \`[data-message-author-role="assistant"]\` / \`[data-message-role="assistant"]\`, then recognizes \`article[data-testid*="conversation-turn"]\` only when its own or nested role is \`assistant\`. On trusted capture-phase \`pointerdown\`, post exactly:

\`\`\`javascript
{
  version: 3,
  event: "trustedInteraction",
  documentToken: documentToken,
  interactionKind: "assistantPointer"
}
\`\`\`

Do not inspect or send button text, aria labels, response text, DOM paths, HTML, URLs, clipboard, or selection. Keep the existing manual-scroll listeners and \`programmaticScrollGuardUntil\` unchanged. Expose the classifier hook only in DEBUG so Release has no test API.

- [ ] **Step 4: Run extraction/bridge tests and verify GREEN**

Run the same command. Expected: script contract, DOM fixture, and synthetic-event rejection tests pass; existing response extraction and scroll tests remain green.

- [ ] **Step 5: Commit**

\`\`\`bash
git add FloatTabs/Web/ChatGPTResponseExtraction.swift FloatTabsTests/ChatGPTResponseExtractionTests.swift FloatTabsTests/ChatGPTResponseBridgeTests.swift
git commit -m "feat: emit trusted assistant pointer interactions"
\`\`\`

### Task 3: Validate and route trusted interactions through the production bridge and pool

**Files:**
- Modify: \`FloatTabs/Web/ChatGPTResponseBridge.swift\`
- Modify: \`FloatTabs/Web/WebViewPool.swift\`
- Test: \`FloatTabsTests/ChatGPTResponseBridgeTests.swift\`

**Interfaces:**
- Consumes: \`ChatGPTTrustedPageInteractionKind\` and the existing bridge identity/token/frame/origin validation.
- Produces: \`onTrustedInteraction: @MainActor (UUID, ChatGPTTrustedPageInteractionKind, String) -> Void\` from \`ChatGPTResponseBridge\` through \`WebViewPool\`.

- [ ] **Step 1: Write failing bridge validation tests**

Add tests using the existing DEBUG normalized-event seam for assistant-pointer forwarding and rejection of the old token. Add message-protocol/static tests for fixed \`trustedInteraction\`, \`assistantPointer\`, and omission of content fields. Extend native validation coverage so wrong WebView, non-main-frame, unsupported host, non-HTTP(S), wrong version, invalid kind, and stale token produce no interaction callback. The DEBUG helper must be absent from Release compilation by remaining under \`#if DEBUG\`.

- [ ] **Step 2: Run bridge tests and verify RED**

Run the bridge-focused command from Task 2. Expected: the new handler initializer, enum parsing, or debug forwarding assertions fail because the route is missing.

- [ ] **Step 3: Implement minimal bridge and pool routing**

Add the trusted-interaction callback to \`ChatGPTResponseBridge\` and \`WebViewPool\`. In \`ChatGPTResponseBridge.userContentController\`, keep the existing first guard unchanged, then accept only version 3, a valid current document token, and a \`ChatGPTTrustedPageInteractionKind\` raw value. Drop everything else before invoking the callback. Add a DEBUG helper that models only an already trust-admitted normalized event and validates the current document token. Do not alter response extraction payload parsing or runtime reset behavior.

- [ ] **Step 4: Run bridge tests and verify GREEN**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -only-testing:FloatTabsTests/ChatGPTResponseBridgeTests -only-testing:FloatTabsTests/ChatGPTResponseExtractionTests
\`\`\`

Expected: all bridge and extraction tests pass with all existing response lifecycle tests intact.

- [ ] **Step 5: Commit**

\`\`\`bash
git add FloatTabs/Web/ChatGPTResponseBridge.swift FloatTabs/Web/WebViewPool.swift FloatTabsTests/ChatGPTResponseBridgeTests.swift
git commit -m "feat: route validated trusted interactions"
\`\`\`

### Task 4: Use the interaction surface for unread acknowledgement and add U1 regressions

**Files:**
- Modify: \`FloatTabs/Panel/PanelController.swift\`
- Test: \`FloatTabsTests/WebAttentionCrossFeatureTests.swift\`
- Test: \`FloatTabsTests/RuntimeDiagnosticsTests.swift\` only if a focused diagnostics assertion belongs there; otherwise keep diagnostics coverage in cross-feature tests.

**Interfaces:**
- Consumes: \`AttentionPresentation.isInteractionSurfacePresented\`, pool trusted-interaction callback, and existing unread acknowledgement authority.
- Produces: \`trusted_assistant_pointer\` diagnostics source and \`interaction_surface_presented\` boolean in all acknowledgement diagnostics.

- [ ] **Step 1: Write failing U1 integration and diagnostics tests**

Add or extend real production-path tests for:

1. Hover-scroll: unread + current pooled WebView + visible source + non-key presentation + current document trusted manual scroll clears unread; attempt and acknowledged events have source \`trusted_manual_scroll\`, \`presentation_visible=false\`, \`web_window_key=false\`, and \`interaction_surface_presented=true\`.
2. Hidden source: valid trusted manual scroll leaves unread and records \`not_actually_presented\` with \`interaction_surface_presented=false\`.
3. Inactive Hot WebView: a resident non-current Slot with unread remains unread after a valid current-document interaction.
4. Assistant pointer/copy action: an assistant pointer clears unread and records source \`trusted_assistant_pointer\`; no button text or content is present in diagnostics.
5. Sidebar/composer pointer: no event reaches acknowledgement and unread remains set.
6. Stale token, wrong WebView, non-main frame, unsupported origin, and invalid protocol: unread remains and no acknowledgement attempt is emitted.
7. Speech manual-scroll callback still reaches \`assistantSpeechCoordinator.handleManualScroll\`; programmatic speech-follow remains non-acknowledging.
8. Existing explicit selection and completion regressions remain strict, including pinned/non-key completion staying unread.

- [ ] **Step 2: Run the U1 integration tests and verify RED**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -only-testing:FloatTabsTests/WebAttentionCrossFeatureTests
\`\`\`

Expected: hover-scroll non-key and assistant-pointer tests fail because acknowledgement still gates on \`presentationVisible\` and the PanelController/pool route is absent.

- [ ] **Step 3: Implement the minimal PanelController route**

Extend \`UnreadPresentationFacts\` with \`interactionSurfacePresented\`, derive it from the same gathered \`AttentionPresentation.Facts\`, and add \`interaction_surface_presented\` to acknowledgement attempt, skipped, and acknowledged diagnostics. Add \`.trustedAssistantPointer\` to the fixed diagnostic source enum. Change only \`acknowledgeUnreadAfterTrustedPageInteraction\` to gate on \`attempt.facts.interactionSurfacePresented\`; leave completion \`userVisibleAtCompletion\`, explicit selection, manual speech, and attention authority unchanged. Wire the pool callbacks so manual scroll still calls speech handling before acknowledgement, while assistant pointer calls only unread acknowledgement.

Use a DEBUG-only facts override/scoped seam for deterministic non-key integration tests; it must not exist in Release and must not change production topology or state ownership.

- [ ] **Step 4: Run focused U1 tests and verify GREEN**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' \\
  -only-testing:FloatTabsTests/UnreadResponseTests \\
  -only-testing:FloatTabsTests/WebAttentionCrossFeatureTests \\
  -only-testing:FloatTabsTests/WebAttentionPresentationTests \\
  -only-testing:FloatTabsTests/ChatGPTResponseBridgeTests \\
  -only-testing:FloatTabsTests/ChatGPTResponseExtractionTests \\
  -only-testing:FloatTabsTests/RuntimeDiagnosticsTests \\
  -only-testing:FloatTabsTests/RuntimeDiagnosticsPrivacyTests \\
  -only-testing:FloatTabsTests/AssistantSpeechCoordinatorTests
\`\`\`

Expected: all focused tests pass with privacy assertions unchanged.

- [ ] **Step 5: Commit**

\`\`\`bash
git add FloatTabs/Panel/PanelController.swift FloatTabsTests/WebAttentionCrossFeatureTests.swift FloatTabsTests/RuntimeDiagnosticsTests.swift
git commit -m "fix: acknowledge unread on trusted page interaction"
\`\`\`

### Task 5: Whole-branch verification and PR handoff

**Files:**
- No additional production changes unless a test-proven U1 regression requires a fix.

- [ ] **Step 1: Run full XCTest and compare failures to exact-main baseline**

Run:

\`\`\`bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64'
\`\`\`

Expected: U1 tests pass; any failures must be compared with the recorded exact-main baseline before being called baseline.

- [ ] **Step 2: Run Debug and Release arm64 builds**

\`\`\`bash
xcodebuild build -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64'
xcodebuild build -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Release -destination 'platform=macOS,arch=arm64'
lipo -archs "$HOME/Library/Developer/Xcode/DerivedData/FloatTabs-"*/Build/Products/Release/FloatTabs.app/Contents/MacOS/FloatTabs
\`\`\`

Expected: both builds succeed and the Release executable reports \`arm64\`.

- [ ] **Step 3: Run hygiene and scope checks**

\`\`\`bash
git diff --check origin/main...HEAD
git diff --exit-code origin/main...HEAD -- Package.resolved
git diff --name-only origin/main...HEAD | rg 'ChatGPTAttentionBridge|ChatGPTUnreadResponseCoordinator|UnreadResponseStore|Package.resolved' && exit 1 || true
git status --short --branch
\`\`\`

Expected: no diff-check errors, no Package.resolved diff, no forbidden source changes, and a clean branch.

- [ ] **Step 4: Push and create the Draft PR**

\`\`\`bash
git push -u origin fix/unread-trusted-interaction-u1
gh pr create --draft --base main --head fix/unread-trusted-interaction-u1 \\
  --title "fix: acknowledge unread on trusted page interaction" \\
  --body "Implements Phase U1 Trusted Page Interaction Acknowledgement from exact main baseline. Preserves completion, attention, persistence, and response identity semantics."
\`\`\`

Expected: one Draft PR, Open and Unmerged, with the requested title.

- [ ] **Step 5: Wait for required remote checks**

\`\`\`bash
gh pr checks <PR_NUMBER> --watch --interval 10
\`\`\`

Expected: \`Build & Test (Apple Silicon arm64)\` and \`QA DMG\` pass. Do not mark ready or merge.
