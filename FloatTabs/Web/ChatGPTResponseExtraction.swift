import Foundation
import WebKit

/// Stable identity for unread ownership. This is deliberately independent
/// from SpeechResponseIdentity, whose document-scoped locator semantics are
/// part of the speech protocol.
struct ChatGPTResponseIdentity: Equatable, Hashable, Sendable {
    static let prefix = "message:"
    static let stableAttributeNames = ["data-message-id", "data-message-uuid"]
    static let suffixLengthRange = 1...160
    static let canonicalLengthRange = 9...168

    let rawValue: String

    init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    init?(stableValue: String) {
        self.init(rawValue: Self.prefix + stableValue)
    }

    static func parse(_ value: String?) -> ChatGPTResponseIdentity? {
        guard let value else { return nil }
        return ChatGPTResponseIdentity(rawValue: value)
    }

    static func isValid(_ value: String) -> Bool {
        guard canonicalLengthRange.contains(value.count),
              value.hasPrefix(prefix) else {
            return false
        }
        let suffix = String(value.dropFirst(prefix.count))
        return suffixLengthRange.contains(suffix.count)
            && suffix.range(
                of: #"^[A-Za-z0-9._:-]+$"#,
                options: .regularExpression
            ) != nil
    }

    /// Shared JS policy used by both the attention and response scripts.
    /// `isRendered` is intentionally supplied by the host script so both
    /// scripts keep their existing rendering semantics.
    static let sharedDOMHelperSource = """
          const RESPONSE_STABLE_ATTRIBUTE_NAMES = ["data-message-id", "data-message-uuid"];
          const STOP_SELECTORS = [
            '[data-testid="stop-button"]',
            '[data-testid="fruitjuice-stop-button"]'
          ];
          const STOP_SEMANTIC_LABELS = new Set([
            "stop",
            "stop generating",
            "stop generating response",
            "stop streaming"
          ]);
          const RESPONSE_ACTION_LABELS = new Set([
            "regenerate",
            "regenerate response",
            "regenerate answer"
          ]);
          const RESPONSE_CONTENT_SELECTOR =
            'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table,' +
            'math,.katex-display,.katex,mjx-container,' +
            '[data-math],[data-latex],[data-tex],[role="math"]';
          const RESPONSE_EXCLUDED_SELECTOR =
            'script,style,noscript,button,[role="button"],[role="toolbar"],toolbar,' +
            '[aria-hidden="true"],svg,[data-testid*="action"],[data-testid*="toolbar"],' +
            'h4[data-conversation-role="assistant"]';

          const safeCanonicalStableValue = (value) => {
            if (!value || value.length > 160) return null;
            return /^[A-Za-z0-9._:-]+$/.test(value) ? value : null;
          };

          const normalizedSemanticLabel = (value) => {
            if (typeof value !== "string") return "";
            return value.trim().toLocaleLowerCase().replace(/\\s+/g, " ");
          };

          const hasStopSemanticLabel = (element) => {
            return ["aria-label", "title"].some((attribute) =>
              STOP_SEMANTIC_LABELS.has(
                normalizedSemanticLabel(element.getAttribute(attribute))
              )
            );
          };

          const isEnabled = (element) =>
            !element.disabled && element.getAttribute("aria-disabled") !== "true";

          const isResponseAction = (element) => {
            if (!element
                || !element.matches
                || !element.matches('button,[role="button"]')
                || !isRendered(element)
                || !isEnabled(element)) {
              return false;
            }
            return ["aria-label", "title"].some((attribute) =>
              RESPONSE_ACTION_LABELS.has(
                normalizedSemanticLabel(element.getAttribute(attribute))
              )
            );
          };

          const responseActions = (root) => {
            const controls = [root].concat(
              Array.from(root.querySelectorAll('button,[role="button"]'))
            );
            return controls.filter(isResponseAction);
          };

          const isComposerContainer = (root) =>
            Boolean(root && root.matches && root.matches(
              'input,textarea,[contenteditable="true"],[role="textbox"]'
            ));

          const hasResponseContent = (root) => {
            const candidates = [];
            if (root && root.matches && root.matches(RESPONSE_CONTENT_SELECTOR)) {
              candidates.push(root);
            }
            candidates.push(...Array.from(root.querySelectorAll(RESPONSE_CONTENT_SELECTOR)));
            return candidates.some(
              (element) => isRendered(element)
                && !element.closest(RESPONSE_EXCLUDED_SELECTOR)
            );
          };

          const hasNonAssistantOwnershipMarker = (root) => {
            const selector = [
              '[data-message-author-role="user"]',
              '[data-message-role="user"]',
              '[data-testid*="conversation-turn-user"]',
              '[data-turn="user"]',
              '[data-conversation-role="user"]',
              '[data-user-message-bubble]',
              'input,textarea,[contenteditable="true"],[role="textbox"]',
              '[role="status"],[data-testid*="status"],[role="alert"]',
              '[aria-live]:not([aria-live="off"])'
            ].join(',');
            return Boolean(
              (root.matches && root.matches(selector))
                || (root.querySelector && root.querySelector(selector))
            );
          };

          const ASSISTANT_ROLE_MARKER_SELECTOR =
            '[data-message-author-role="assistant"],[data-message-role="assistant"]';
          const CONTENT_UNIT_SELECTOR = '[data-content-search-unit-key]';
          const ASSISTANT_CONTENT_UNIT_MARKER_SELECTOR =
            '[data-conversation-role="assistant"],[data-chatgpt-agent-turn-start]';

          const isAssistantSemanticConversationTurn = (turn) => {
            if (!turn || !turn.matches
                || !turn.matches('[data-testid*="conversation-turn"]')) {
              return false;
            }
            return turn.getAttribute('data-turn') === 'assistant'
              || turn.getAttribute('data-message-author-role') === 'assistant'
              || turn.getAttribute('data-message-role') === 'assistant'
              || Boolean(turn.querySelector(ASSISTANT_ROLE_MARKER_SELECTOR));
          };

          const hasMarkerWithinContentUnit = (unit, selector) => {
            if (unit.matches && unit.matches(selector)) return true;
            return Array.from(unit.querySelectorAll(selector)).some(
              (marker) => marker.closest(CONTENT_UNIT_SELECTOR) === unit
            );
          };

          const hasResponseContentWithinContentUnit = (unit) => {
            const candidates = [];
            if (unit.matches && unit.matches(RESPONSE_CONTENT_SELECTOR)) {
              candidates.push(unit);
            }
            candidates.push(...Array.from(unit.querySelectorAll(RESPONSE_CONTENT_SELECTOR)));
            return candidates.some((element) =>
              element.closest(CONTENT_UNIT_SELECTOR) === unit
                && isRendered(element)
                && !element.closest(RESPONSE_EXCLUDED_SELECTOR)
            );
          };

          const isAssistantContentUnit = (unit) => Boolean(
            unit
              && unit.matches
              && unit.matches(CONTENT_UNIT_SELECTOR)
              && isRendered(unit)
              && !isComposerContainer(unit)
              && !hasNonAssistantOwnershipMarker(unit)
              && hasMarkerWithinContentUnit(
                unit,
                ASSISTANT_CONTENT_UNIT_MARKER_SELECTOR
              )
              && hasResponseContentWithinContentUnit(unit)
          );

          const isPositiveAssistantRoot = (root) => Boolean(
            root
              && isRendered(root)
              && !isComposerContainer(root)
              && !hasNonAssistantOwnershipMarker(root)
          );

          const nearestSemanticConversationTurn = (element) => {
            let ancestor = element && element.parentElement;
            while (ancestor
                   && ancestor !== document.body
                   && ancestor !== document.documentElement) {
              if (ancestor.matches
                  && ancestor.matches('[data-testid*="conversation-turn"]')) {
                return ancestor;
              }
              ancestor = ancestor.parentElement;
            }
            return null;
          };

          // Completed-response controls may lack assistant-role attributes,
          // so Regenerate fallback requires a positive semantic turn boundary.
          // Never widen that ownership to a generic ancestor.
          const latestRegenerateOwnedResponse = () => {
            const controls = Array.from(
              document.querySelectorAll('button,[role="button"]')
            ).filter((element) => isResponseAction(element));
            for (let index = controls.length - 1; index >= 0; index -= 1) {
              const control = controls[index];
              const turn = nearestSemanticConversationTurn(control);
              if (turn
                  && isRendered(turn)
                  && !isComposerContainer(turn)
                  && responseActions(turn).length === 1
                  && hasResponseContent(turn)
                  && !hasNonAssistantOwnershipMarker(turn)) {
                return turn;
              }
            }
            return null;
          };

          const canonicalResponseIdentityFor = (element) => {
            if (!element || typeof element.getAttribute !== 'function') return null;
            for (const attributeName of RESPONSE_STABLE_ATTRIBUTE_NAMES) {
              const stable = safeCanonicalStableValue(
                element.getAttribute(attributeName)
              );
              if (stable) return 'message:' + stable;
            }
            return null;
          };

          const positiveAssistantRoots = () => {
            const candidates = [];
            const seen = new Set();
            const addCandidate = (root) => {
              if (!isPositiveAssistantRoot(root) || seen.has(root)) return;
              seen.add(root);
              candidates.push(root);
            };

            Array.from(document.querySelectorAll(ASSISTANT_ROLE_MARKER_SELECTOR))
              .forEach(addCandidate);

            Array.from(document.querySelectorAll(
              '[data-testid*="conversation-turn"][data-turn="assistant"]'
            )).forEach(addCandidate);

            Array.from(document.querySelectorAll('[data-testid*="conversation-turn"]'))
              .filter(isAssistantSemanticConversationTurn)
              .forEach(addCandidate);

            Array.from(document.querySelectorAll(CONTENT_UNIT_SELECTOR))
              .filter(isAssistantContentUnit)
              .forEach(addCandidate);

            const narrowed = candidates.filter((candidate) =>
              !candidates.some((other) =>
                other !== candidate
                  && candidate.contains(other)
                  && hasResponseContent(other)
              )
            );
            return narrowed.sort((left, right) => {
              if (left === right) return 0;
              const position = left.compareDocumentPosition(right);
              if (position & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
              if (position & Node.DOCUMENT_POSITION_PRECEDING) return 1;
              return 0;
            });
          };

          const assistantResponseRoots = () => {
            const positiveRoots = positiveAssistantRoots();
            if (positiveRoots.length) return positiveRoots;
            const fallback = latestRegenerateOwnedResponse();
            return fallback ? [fallback] : [];
          };

          const assistantResponseRootFor = (eventTarget) => {
            const element = eventTarget && eventTarget.nodeType === Node.ELEMENT_NODE
              ? eventTarget
              : eventTarget?.parentElement;
            if (!element) return null;
            const containingRoots = positiveAssistantRoots().filter(
              (root) => root === element || root.contains(element)
            );
            return containingRoots.reduce((selected, candidate) => {
              if (!selected || selected.contains(candidate)) return candidate;
              return selected;
            }, null);
          };

          const latestAssistantResponseRoot = () => {
            const roots = assistantResponseRoots();
            return roots.length ? roots[roots.length - 1] : null;
          };

          const isGenerating = () => {
            for (const selector of STOP_SELECTORS) {
              const elements = document.querySelectorAll(selector);
              for (const element of elements) {
                if (isRendered(element)) return true;
              }
            }
            const semanticControls = document.querySelectorAll(
              'button[aria-label],button[title],[role="button"][aria-label],[role="button"][title]'
            );
            for (const element of semanticControls) {
              if (isEnabled(element)
                  && hasStopSemanticLabel(element)) {
                if (isRendered(element)) return true;
              }
            }
            return false;
          };
"""
}
struct ChatGPTResponseStatusSnapshot: Equatable, Sendable {
    let documentToken: String
    let responseIdentity: ChatGPTResponseIdentity?
    let generating: Bool
}

struct ChatGPTTrustedInteractionEvent: Equatable, Sendable {
    let kind: ChatGPTTrustedPageInteractionKind
    let documentToken: String
    let responseIdentity: ChatGPTResponseIdentity?
    let responseComplete: Bool
}

/// Swift-owned protocol model for the independent one-shot ChatGPT response
/// bridge. It contains only structured response blocks in transient memory.
enum ChatGPTResponseMessageKind: String, Equatable, Sendable {
    case response
    case empty
}

enum ChatGPTTrustedPageInteractionKind: String, Equatable, Sendable {
    case manualScroll
    case assistantPointer
}

enum ChatGPTResponseExtractionPath: String, CaseIterable, Equatable, Sendable {
    case explicit
    case semanticTurn = "semantic_turn"
    case contentUnit = "content_unit"
    case fallback
    case none
}

enum ChatGPTSpeechOwnershipCategory: String, CaseIterable, Equatable, Sendable {
    case assistantOwned = "assistant_owned"
    case userOwned = "user_owned"
    case composer
    case statusLive = "status_live"
    case unknown
}

enum ChatGPTResponseRootElementCategory: String, Equatable, Sendable {
    case article
    case div
    case section
    case other
    case none
}

/// Fixed, structural metadata produced beside the real response payload. This
/// model deliberately has no field capable of holding DOM or response text.
struct ChatGPTSpeechExtractionDiagnostics: Equatable, Sendable {
    static let maximumBlockCount = 1024

    let selectedPath: ChatGPTResponseExtractionPath
    let rootElement: ChatGPTResponseRootElementCategory
    let composerMarkerPresent: Bool
    let userMarkerPresent: Bool
    let assistantMarkerPresent: Bool
    let statusMarkerPresent: Bool
    let alertMarkerPresent: Bool
    let liveRegionMarkerPresent: Bool
    let blockOwnership: [ChatGPTSpeechOwnershipCategory]

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "selected_path": .string(selectedPath.rawValue),
            "root_element": .string(rootElement.rawValue),
            "composer_marker_present": .bool(composerMarkerPresent),
            "user_marker_present": .bool(userMarkerPresent),
            "assistant_marker_present": .bool(assistantMarkerPresent),
            "status_marker_present": .bool(statusMarkerPresent),
            "alert_marker_present": .bool(alertMarkerPresent),
            "live_region_marker_present": .bool(liveRegionMarkerPresent),
            "block_count": .integer(Int64(blockOwnership.count)),
            "block_ownership_sequence": .string(
                blockOwnership.map(\.rawValue).joined(separator: ",")
            )
        ]
        for category in ChatGPTSpeechOwnershipCategory.allCases {
            fields["block_\(category.rawValue)_count"] = .integer(
                Int64(blockOwnership.filter { $0 == category }.count)
            )
        }
        return fields
    }

    static func parse(_ value: Any?) -> ChatGPTSpeechExtractionDiagnostics? {
        guard let body = value as? [String: Any],
              let rawPath = body["selectedPath"] as? String,
              let selectedPath = ChatGPTResponseExtractionPath(rawValue: rawPath),
              let rawRoot = body["rootElement"] as? String,
              let rootElement = ChatGPTResponseRootElementCategory(rawValue: rawRoot),
              let composerMarkerPresent = body["composerMarkerPresent"] as? Bool,
              let userMarkerPresent = body["userMarkerPresent"] as? Bool,
              let assistantMarkerPresent = body["assistantMarkerPresent"] as? Bool,
              let statusMarkerPresent = body["statusMarkerPresent"] as? Bool,
              let alertMarkerPresent = body["alertMarkerPresent"] as? Bool,
              let liveRegionMarkerPresent = body["liveRegionMarkerPresent"] as? Bool,
              let rawOwnership = body["blockOwnership"] as? [String],
              rawOwnership.count <= maximumBlockCount else {
            return nil
        }
        let blockOwnership = rawOwnership.compactMap(
            ChatGPTSpeechOwnershipCategory.init(rawValue:)
        )
        guard blockOwnership.count == rawOwnership.count else { return nil }
        return ChatGPTSpeechExtractionDiagnostics(
            selectedPath: selectedPath,
            rootElement: rootElement,
            composerMarkerPresent: composerMarkerPresent,
            userMarkerPresent: userMarkerPresent,
            assistantMarkerPresent: assistantMarkerPresent,
            statusMarkerPresent: statusMarkerPresent,
            alertMarkerPresent: alertMarkerPresent,
            liveRegionMarkerPresent: liveRegionMarkerPresent,
            blockOwnership: blockOwnership
        )
    }
}


enum ChatGPTResponseProtocol {
    static let currentVersion = 3

    static func isOpaqueIdentifier(_ value: String) -> Bool {
        value.count >= 8
            && value.count <= 256
            && value.range(
                of: #"^[A-Za-z0-9._:-]+$"#,
                options: .regularExpression
            ) != nil
    }
}

/// Compile-only compatibility payload retained until WP5. Production WebKit
/// response handling uses ChatGPTResponseProtocol and never requests a body.
struct ChatGPTResponsePayload: Equatable, Sendable {
    static let currentVersion = ChatGPTResponseProtocol.currentVersion
    static let responseKind = ChatGPTResponseMessageKind.response.rawValue
    static let emptyKind = ChatGPTResponseMessageKind.empty.rawValue

    let version: Int
    let kind: ChatGPTResponseMessageKind
    let requestID: String
    let documentToken: String
    let responseID: String?
    let blocks: [SpeechContentBlock]
    let speechDiagnostics: ChatGPTSpeechExtractionDiagnostics?

    init(
        version: Int,
        kind: ChatGPTResponseMessageKind,
        requestID: String,
        documentToken: String,
        responseID: String?,
        blocks: [SpeechContentBlock],
        speechDiagnostics: ChatGPTSpeechExtractionDiagnostics? = nil
    ) {
        self.version = version
        self.kind = kind
        self.requestID = requestID
        self.documentToken = documentToken
        self.responseID = responseID
        self.blocks = blocks
        self.speechDiagnostics = speechDiagnostics
    }
}

@MainActor
enum ChatGPTResponseExtraction {
    static let contentWorldName = "FloatTabsChatGPTResponse"
    static let messageHandlerName = "floatTabsChatGPTResponse"
    static let contentWorld = WKContentWorld.world(name: contentWorldName)
    static let scriptSource = makeScriptSource()

    private static func makeScriptSource() -> String {
        let hostGate = ChatGPTAttentionBridge.hostGateExpression()
#if DEBUG
        let debugAssistantPointerClassifier = """
          globalThis.__floatTabsDebugClassifyAssistantPointerTargetV3 = (selector) => {
            const target = typeof selector === 'string'
              ? document.querySelector(selector)
              : null;
            return assistantResponseRootFor(target) ? 'assistantPointer' : null;
          };
        """
#else
        let debugAssistantPointerClassifier = ""
#endif
        return """
        (() => {
          "use strict";
          if (window.top !== window) { return; }
          const host = (location.hostname || '').toLowerCase();
          const supportedHost = \(hostGate);
          if (!supportedHost) { return; }

          const handler = () => {
            try {
              return window.webkit && window.webkit.messageHandlers
                && window.webkit.messageHandlers["floatTabsChatGPTResponse"];
            } catch (_) {
              return undefined;
            }
          };
          if (!handler()) { return; }

          const documentToken = (window.crypto && crypto.randomUUID)
            ? crypto.randomUUID()
            : "doc-" + Date.now().toString(36) + "-" +
              Math.random().toString(36).slice(2, 14);

          const isRendered = (element) => {
            if (!element || !element.isConnected) return false;
            if (element.getClientRects().length === 0) return false;
            const style = window.getComputedStyle(element);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.visibility !== 'collapse';
          };

          \(ChatGPTResponseIdentity.sharedDOMHelperSource)

          const postManualScroll = () => {
            const target = handler();
            if (!target) return;
            const latestRoot = latestAssistantResponseRoot();
            const generating = isGenerating();
            target.postMessage({
              version: \(ChatGPTResponseProtocol.currentVersion),
              event: "manualScroll",
              documentToken: documentToken,
              latestResponseIdentity: canonicalResponseIdentityFor(latestRoot),
              latestResponseComplete: Boolean(latestRoot) && !generating
            });
          };

          const postTrustedAssistantPointer = (root) => {
            const target = handler();
            if (!target) return;
            const latestRoot = latestAssistantResponseRoot();
            const generating = isGenerating();
            target.postMessage({
              version: \(ChatGPTResponseProtocol.currentVersion),
              event: "trustedInteraction",
              documentToken: documentToken,
              interactionKind: "assistantPointer",
              responseIdentity: canonicalResponseIdentityFor(root),
              responseComplete: root !== latestRoot || !generating
            });
          };

          const postDocumentReady = () => {
            const target = handler();
            if (!target) return;
            target.postMessage({
              version: \(ChatGPTResponseProtocol.currentVersion),
              event: "documentReady",
              documentToken: documentToken
            });
          };

          const announceDocumentReady = () => {
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', postDocumentReady, {
                once: true
              });
              return;
            }
            Promise.resolve().then(postDocumentReady);
          };

          // didCommit resets the native live identity. Announcing after the
          // document reaches DOMContentLoaded prevents the document-start
          // script from being erased by that replacement boundary.
          announceDocumentReady();

          const isScrollKey = (event) =>
            event.key === 'PageUp'
              || event.key === 'PageDown'
              || event.key === 'Home'
              || event.key === 'End'
              || event.key === ' '
              || event.code === 'Space';

          const isEditableTarget = (eventTarget) => {
            let element = eventTarget && eventTarget.nodeType === Node.ELEMENT_NODE
              ? eventTarget
              : eventTarget?.parentElement;
            while (element) {
              if (element.matches('input,textarea,select')) return true;
              if (element.hasAttribute('contenteditable')) {
                const state = (element.getAttribute('contenteditable') || '')
                  .toLowerCase();
                if (state === 'false') return false;
                return state === '' || state === 'true' || state === 'plaintext-only';
              }
              element = element.parentElement;
            }
            return false;
          };

          document.addEventListener('wheel', (event) => {
            if (event.isTrusted) postManualScroll();
          }, true);
          document.addEventListener('keydown', (event) => {
            if (event.isTrusted
                && isScrollKey(event)
                && !isEditableTarget(event.target)) {
              postManualScroll();
            }
          }, true);
          document.addEventListener('pointerdown', (event) => {
            if (!event.isTrusted) return;
            const assistantRoot = assistantResponseRootFor(event.target);
            if (assistantRoot) {
              postTrustedAssistantPointer(assistantRoot);
            }
            const root = document.documentElement;
            const likelyScrollbar = event.clientX >= root.clientWidth
              || event.clientY >= root.clientHeight;
            if (likelyScrollbar) postManualScroll();
          }, true);

          globalThis.__floatTabsChatGPTResponseIdentitySnapshotV1 = () => {
            const latestRoot = latestAssistantResponseRoot();
            return {
              version: 1,
              documentToken: documentToken,
              responseIdentity: canonicalResponseIdentityFor(latestRoot),
              generating: isGenerating()
            };
          };

          \(debugAssistantPointerClassifier)
        })();
        """
    }
}
