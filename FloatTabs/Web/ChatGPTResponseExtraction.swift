import Foundation
import WebKit

/// Stable identity for unread ownership. This is deliberately independent
/// from any document-scoped content locator semantics.
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
            "stop response",
            "stop streaming",
            "停止",
            "停止生成",
            "停止回答",
            "停止流式传输",
            "停止输出",
            "停止响应"
          ]);
          const RESPONSE_ACTION_LABELS = new Set([
            "regenerate",
            "regenerate response",
            "regenerate answer",
            "retry",
            "重新生成",
            "重新生成回复",
            "重试"
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
                || !isEnabled(element)) {
              return false;
            }
            const hasMatchingLabel = ["aria-label", "title"].some((attribute) =>
              RESPONSE_ACTION_LABELS.has(
                normalizedSemanticLabel(element.getAttribute(attribute))
              )
            );
            return hasMatchingLabel && isRendered(element);
          };

          const responseActions = (root) => {
            const controls = [root].concat(
              Array.from(root.querySelectorAll(
                'button[aria-label],button[title],[role="button"][aria-label],[role="button"][title]'
              ))
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
              (element) => !element.closest(RESPONSE_EXCLUDED_SELECTOR)
                && isRendered(element)
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
          const COMBINED_ASSISTANT_CANDIDATE_SELECTOR =
            ASSISTANT_ROLE_MARKER_SELECTOR +
            ',[data-testid*="conversation-turn"][data-turn="assistant"]' +
            ',[data-testid*="conversation-turn"],' +
            CONTENT_UNIT_SELECTOR;

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
                && !element.closest(RESPONSE_EXCLUDED_SELECTOR)
                && isRendered(element)
            );
          };

          const isAssistantContentUnit = (unit) => Boolean(
            unit
              && unit.matches
              && unit.matches(CONTENT_UNIT_SELECTOR)
              && !isComposerContainer(unit)
              && !hasNonAssistantOwnershipMarker(unit)
              && hasMarkerWithinContentUnit(
                unit,
                ASSISTANT_CONTENT_UNIT_MARKER_SELECTOR
              )
              && isRendered(unit)
              && hasResponseContentWithinContentUnit(unit)
          );

          const isPositiveAssistantRoot = (root) => Boolean(
            root
              && !isComposerContainer(root)
              && !hasNonAssistantOwnershipMarker(root)
              && isRendered(root)
          );

          const isPositiveAssistantCandidate = (candidate) => {
            if (!candidate || !candidate.matches) return false;
            if ((candidate.matches(ASSISTANT_ROLE_MARKER_SELECTOR)
                 || isAssistantSemanticConversationTurn(candidate))
                && isPositiveAssistantRoot(candidate)) {
              return true;
            }
            if (candidate.matches(CONTENT_UNIT_SELECTOR)
                && isAssistantContentUnit(candidate)) {
              return true;
            }
            return false;
          };

          const hasNarrowerPositiveAssistantDescendant = (candidate) => {
            if (!candidate || typeof candidate.querySelectorAll !== 'function') {
              return false;
            }
            const descendants = candidate.querySelectorAll(
              COMBINED_ASSISTANT_CANDIDATE_SELECTOR
            );
            for (let index = 0; index < descendants.length; index += 1) {
              const other = descendants[index];
              if (other !== candidate
                  && isPositiveAssistantCandidate(other)
                  && hasResponseContent(other)) {
                return true;
              }
            }
            return false;
          };

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
            if (typeof document.querySelector === 'function'
                && !document.querySelector('[data-testid*="conversation-turn"]')) {
              return null;
            }
            const controls = document.querySelectorAll(
              'button[aria-label],button[title],[role="button"][aria-label],[role="button"][title]'
            );
            for (let index = controls.length - 1; index >= 0; index -= 1) {
              const control = controls[index];
              if (!isResponseAction(control)) continue;
              const turn = nearestSemanticConversationTurn(control);
              if (turn
                  && !isComposerContainer(turn)
                  && !hasNonAssistantOwnershipMarker(turn)
                  && isRendered(turn)
                  && responseActions(turn).length === 1
                  && hasResponseContent(turn)) {
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
            const candidates = Array.from(
              document.querySelectorAll(COMBINED_ASSISTANT_CANDIDATE_SELECTOR)
            ).filter(isPositiveAssistantCandidate);
            return candidates.filter((candidate) =>
              !hasNarrowerPositiveAssistantDescendant(candidate)
            );
          };

          const assistantResponseRoots = () => {
            const positiveRoots = positiveAssistantRoots();
            if (positiveRoots.length) return positiveRoots;
            const fallback = latestRegenerateOwnedResponse();
            return fallback ? [fallback] : [];
          };

          const assistantResponseRootFor = (eventTarget) => {
            let cursor = eventTarget && eventTarget.nodeType === Node.ELEMENT_NODE
              ? eventTarget
              : eventTarget?.parentElement;
            while (cursor
                   && cursor !== document.body
                   && cursor !== document.documentElement) {
              if (typeof cursor.matches === 'function'
                  && cursor.matches(COMBINED_ASSISTANT_CANDIDATE_SELECTOR)
                  && isPositiveAssistantCandidate(cursor)) {
                if (!hasNarrowerPositiveAssistantDescendant(cursor)) {
                  return cursor;
                }
                return null;
              }
              cursor = cursor.parentElement;
            }
            return null;
          };

          const latestAssistantResponseRoot = () => {
            const candidates = document.querySelectorAll(
              COMBINED_ASSISTANT_CANDIDATE_SELECTOR
            );
            for (let index = candidates.length - 1; index >= 0; index -= 1) {
              const candidate = candidates[index];
              if (isPositiveAssistantCandidate(candidate)
                  && !hasNarrowerPositiveAssistantDescendant(candidate)) {
                return candidate;
              }
            }
            return latestRegenerateOwnedResponse();
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

enum ChatGPTTrustedPageInteractionKind: String, Equatable, Sendable {
    case manualScroll
    case assistantPointer
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

          const WHEEL_SCROLL_COALESCE_MS = 200;
          let lastWheelScrollAt = -WHEEL_SCROLL_COALESCE_MS;

          document.addEventListener('wheel', (event) => {
            if (!event.isTrusted) return;
            const now = Date.now();
            if (now - lastWheelScrollAt < WHEEL_SCROLL_COALESCE_MS) return;
            lastWheelScrollAt = now;
            if (event.isTrusted) postManualScroll();
          }, { capture: true, passive: true });
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
            const nearRightEdge = typeof window.innerWidth !== 'number'
              || event.clientX >= window.innerWidth - 24;
            const nearBottomEdge = typeof window.innerHeight !== 'number'
              || event.clientY >= window.innerHeight - 24;
            if (nearRightEdge || nearBottomEdge) {
              const root = document.documentElement;
              const likelyScrollbar = root && (
                event.clientX >= root.clientWidth
                || event.clientY >= root.clientHeight
              );
              if (likelyScrollbar) postManualScroll();
            }
          }, { capture: true, passive: true });

          globalThis.__floatTabsChatGPTResponseIdentitySnapshotV1 = () => {
            const latestRoot = latestAssistantResponseRoot();
            return {
              version: 1,
              documentToken: documentToken,
              responseIdentity: canonicalResponseIdentityFor(latestRoot),
              generating: isGenerating()
            };
          };

          // One-shot assistant-response preview projection. Reuses the same
          // assistant-root/content/exclusion semantics as identity status; the
          // gathered text is a bounded plain-text window only. No prompt/user
          // or composer content is selected, and no raw HTML is returned.
          const PREVIEW_GATHER_LIMIT = 600;
          globalThis.__floatTabsChatGPTResponsePreviewV1 = () => {
            const latestRoot = latestAssistantResponseRoot();
            const generating = isGenerating();
            if (!latestRoot || generating) {
              return {
                version: 1,
                documentToken: documentToken,
                generating: generating,
                preview: null
              };
            }
            const nodes = [];
            if (latestRoot.matches && latestRoot.matches(RESPONSE_CONTENT_SELECTOR)) {
              nodes.push(latestRoot);
            }
            nodes.push(...Array.from(latestRoot.querySelectorAll(
              RESPONSE_CONTENT_SELECTOR
            )));
            const eligibleNodes = nodes.filter((node) => isRendered(node)
              && !node.matches(RESPONSE_EXCLUDED_SELECTOR)
              && !node.closest(RESPONSE_EXCLUDED_SELECTOR));
            const selectedNodes = new Set(eligibleNodes);
            const topLevelNodes = eligibleNodes.filter((node) => {
              let ancestor = node.parentElement;
              while (ancestor && latestRoot.contains(ancestor)) {
                if (selectedNodes.has(ancestor)) return false;
                ancestor = ancestor.parentElement;
              }
              return true;
            });
            let text = "";
            const appendBounded = (value) => {
              for (const character of value) {
                if (text.length + character.length > PREVIEW_GATHER_LIMIT) return false;
                text += character;
              }
              return true;
            };
            for (const node of topLevelNodes) {
              if (text.length >= PREVIEW_GATHER_LIMIT) break;
              if (text && !/\\s$/.test(text) && !appendBounded(" ")) break;

              const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
              let previousBoundary = null;
              while (walker.nextNode() && text.length < PREVIEW_GATHER_LIMIT) {
                const textNode = walker.currentNode;
                const parent = textNode.parentElement;
                if (!parent
                    || !isRendered(parent)
                    || parent.closest(RESPONSE_EXCLUDED_SELECTOR)) continue;
                const boundary = parent.closest(
                  'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table,td,th'
                ) || node;
                if (previousBoundary && previousBoundary !== boundary
                    && text && !/\\s$/.test(text) && !appendBounded(" ")) break;
                previousBoundary = boundary;
                if (!appendBounded(textNode.nodeValue || "")) break;
              }
            }
            text = text.replace(/[\\f\\n\\r\\t\\v ]+/g, " ").trim();
            return {
              version: 1,
              documentToken: documentToken,
              generating: false,
              preview: text || null
            };
          };

          \(debugAssistantPointerClassifier)
        })();
        """
    }
}
