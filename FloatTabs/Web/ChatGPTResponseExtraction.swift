import Foundation
import WebKit

/// Swift-owned protocol model for the independent one-shot ChatGPT response
/// bridge. It contains only structured response blocks in transient memory.
enum ChatGPTResponseMessageKind: String, Equatable, Sendable {
    case response
    case empty
}

struct ChatGPTResponsePayload: Equatable, Sendable {
    static let currentVersion = 3
    static let responseKind = ChatGPTResponseMessageKind.response.rawValue
    static let emptyKind = ChatGPTResponseMessageKind.empty.rawValue

    let version: Int
    let kind: ChatGPTResponseMessageKind
    let requestID: String
    let documentToken: String
    let responseID: String?
    let blocks: [SpeechContentBlock]

    static func parse(_ body: [String: Any]) -> ChatGPTResponsePayload? {
        guard let version = body["version"] as? Int,
              version == currentVersion,
              let rawKind = body["kind"] as? String,
              let kind = ChatGPTResponseMessageKind(rawValue: rawKind),
              let requestID = body["requestID"] as? String,
              isOpaqueIdentifier(requestID),
              let documentToken = body["documentToken"] as? String,
              isOpaqueIdentifier(documentToken) else {
            return nil
        }

        let responseID = body["responseID"] as? String
        guard responseID == nil || isOpaqueIdentifier(responseID ?? "") else {
            return nil
        }

        let blocks: [SpeechContentBlock]
        if let rawBlocks = body["blocks"] as? [[String: Any]] {
            let parsedBlocks = rawBlocks.compactMap {
                parseBlock(
                    $0,
                    documentToken: documentToken,
                    responseID: responseID
                )
            }
            guard parsedBlocks.count == rawBlocks.count else { return nil }
            blocks = parsedBlocks
        } else {
            blocks = []
        }

        if kind == .response {
            guard responseID != nil, !blocks.isEmpty else { return nil }
        } else if responseID != nil || !blocks.isEmpty {
            return nil
        }

        return ChatGPTResponsePayload(
            version: version,
            kind: kind,
            requestID: requestID,
            documentToken: documentToken,
            responseID: responseID,
            blocks: blocks
        )
    }

    func assigning(slotID: UUID) -> ChatGPTResponsePayload {
        ChatGPTResponsePayload(
            version: version,
            kind: kind,
            requestID: requestID,
            documentToken: documentToken,
            responseID: responseID,
            blocks: blocks.map { block in
                guard let locator = block.sourceLocator else { return block }
                return SpeechContentBlock(
                    kind: block.kind,
                    text: block.text,
                    level: block.level,
                    sourceLocator: locator.assigning(slotID: slotID)
                )
            }
        )
    }

    private static func parseBlock(
        _ body: [String: Any],
        documentToken: String,
        responseID: String?
    ) -> SpeechContentBlock? {
        guard let rawKind = body["kind"] as? String,
              let kind = SpeechContentBlockKind(rawValue: rawKind),
              let text = body["text"] as? String,
              !text.isEmpty,
              let rawLocator = body["sourceLocator"] as? [String: Any],
              let locatorDocumentToken = rawLocator["documentToken"] as? String,
              let locatorResponseID = rawLocator["responseID"] as? String,
              let blockID = rawLocator["blockID"] as? String,
              locatorDocumentToken == documentToken,
              locatorResponseID == responseID,
              isOpaqueIdentifier(locatorDocumentToken),
              isOpaqueIdentifier(locatorResponseID),
              isOpaqueIdentifier(blockID) else {
            return nil
        }
        let level = (body["level"] as? NSNumber)?.intValue
        return SpeechContentBlock(
            kind: kind,
            text: text,
            level: level,
            sourceLocator: SpeechSourceLocator(
                documentToken: locatorDocumentToken,
                responseID: locatorResponseID,
                blockID: blockID
            )
        )
    }

    private static func isOpaqueIdentifier(_ value: String) -> Bool {
        value.count >= 8
            && value.count <= 256
            && value.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil
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
          const responseKeys = new WeakMap();
          const locatorRegistry = new Map();
          const responseLocatorKeys = new Map();
          let nextOpaqueKey = 0;
          let programmaticScrollGuardUntil = 0;
          const MAX_BLOCKS = 256;
          // The speech queue holds at most 64 pending segments. Keeping a
          // larger bounded response-group window leaves room for the current
          // response plus ordinary queued responses without making the
          // document-lifetime registry unbounded.
          const MAX_RESPONSE_GROUPS = 128;
          const MAX_BLOCK_TEXT = 4000;

          const normalizedText = (element) => (element.textContent || '')
            .replace(/\\s+/g, ' ')
            .trim()
            .slice(0, MAX_BLOCK_TEXT);

          const isRendered = (element) => {
            if (!element || !element.isConnected) return false;
            if (element.getClientRects().length === 0) return false;
            const style = window.getComputedStyle(element);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.visibility !== 'collapse';
          };

          const safeStableID = (value) => {
            if (!value || value.length > 160) return null;
            return /^[A-Za-z0-9._:-]+$/.test(value) ? value : null;
          };

          const responseIDFor = (element) => {
            const stable = safeStableID(element.getAttribute('data-message-id'))
              || safeStableID(element.getAttribute('data-message-uuid'))
              || safeStableID(element.id);
            if (stable) return documentToken + ':' + stable;
            const existing = responseKeys.get(element);
            if (existing) return existing;
            nextOpaqueKey += 1;
            const generated = documentToken + ':response-' + nextOpaqueKey;
            responseKeys.set(element, generated);
            return generated;
          };

          const assistantRoots = () => {
            const explicit = Array.from(document.querySelectorAll(
              '[data-message-author-role="assistant"],'
              + '[data-message-role="assistant"]'
            ));
            if (explicit.length) return explicit.filter(isRendered);

            return Array.from(document.querySelectorAll(
              'article[data-testid*="conversation-turn"]'
            )).filter((article) => {
              const role = article.getAttribute('data-message-author-role')
                || article.querySelector('[data-message-author-role]')
                  ?.getAttribute('data-message-author-role');
              return role === 'assistant' && isRendered(article);
            });
          };

          const semanticSelector = 'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table';
          const mathSelector = 'math,.katex-display,.katex,mjx-container';
          const excludedSelector =
            'script,style,noscript,button,[role="button"],[role="toolbar"],toolbar,' +
            '[aria-hidden="true"],svg,[data-testid*="action"],[data-testid*="toolbar"]';

          const isExcluded = (element) =>
            Boolean(element.closest && element.closest(excludedSelector));

          const textWithoutControls = (element) => {
            const clone = element.cloneNode(true);
            clone.querySelectorAll(excludedSelector).forEach((node) => node.remove());
            return (clone.textContent || '').replace(/\\s+/g, ' ').trim();
          };

          const isCanonicalMathRoot = (element) => {
            if (!element.matches || !element.matches(mathSelector)) return false;
            if (!isRendered(element)) return false;
            if (element.matches('.katex-display')) return true;
            if (element.matches('.katex') && element.closest('.katex-display')) return false;
            if (element.matches('.katex-mathml,.katex-html')) return false;
            if (element.matches('math') && element.closest('math') !== element) return false;
            if (element.matches('mjx-container') && element.closest('mjx-container') !== element) {
              return false;
            }
            return true;
          };

          const mathSource = (element) => {
            const annotation = element.querySelector(
              'annotation[encoding="application/x-tex"],' +
              'annotation[encoding="application/tex"],' +
              'annotation[encoding="application/x-latex"]'
            );
            const dataSource = element.getAttribute('data-latex')
              || element.getAttribute('data-tex')
              || element.querySelector('[data-latex]')?.getAttribute('data-latex')
              || element.querySelector('[data-tex]')?.getAttribute('data-tex');
            const ariaSource = element.getAttribute('aria-label')
              || element.getAttribute('alttext')
              || element.querySelector('[aria-label]')?.getAttribute('aria-label');
            const candidate = annotation?.textContent
              || dataSource
              || ariaSource
              || textWithoutControls(element);
            return (candidate || '').replace(/\\s+/g, ' ').trim().slice(0, MAX_BLOCK_TEXT);
          };

          const appendTextPart = (parts, kind, text, level, sourceElement) => {
            const value = (text || '').replace(/\\s+/g, ' ').trim();
            if (!value) return;
            const previous = parts[parts.length - 1];
            if (previous && previous.kind === kind && previous.level === level) {
              previous.text = (previous.text + ' ' + value).trim().slice(0, MAX_BLOCK_TEXT);
            } else {
              parts.push({
                kind: kind,
                text: value.slice(0, MAX_BLOCK_TEXT),
                level: level,
                sourceElement: sourceElement
              });
            }
          };

          const appendInlineParts = (element, kind, level, parts, sourceElement = element) => {
            element.childNodes.forEach((node) => {
              if (node.nodeType === Node.TEXT_NODE) {
                appendTextPart(parts, kind, node.nodeValue || '', level, sourceElement);
                return;
              }
              if (node.nodeType !== Node.ELEMENT_NODE) return;
              if (isExcluded(node)) return;
              if (isCanonicalMathRoot(node)) {
                const source = mathSource(node);
                if (source) {
                  parts.push({
                    kind: node.matches('.katex-display') ? 'mathBlock' : 'mathInline',
                    text: source,
                    level: null,
                    sourceElement: node
                  });
                }
                return;
              }
              appendInlineParts(node, kind, level, parts, sourceElement);
            });
          };

          const appendSemanticBlock = (element, blocks) => {
            const tag = element.tagName.toLowerCase();
            if (tag === 'pre' || tag === 'table') {
              const text = textWithoutControls(element).slice(0, MAX_BLOCK_TEXT);
              if (text) blocks.push({
                kind: tag === 'pre' ? 'code' : 'table',
                text: text,
                level: null,
                sourceElement: element
              });
              return;
            }
            let kind = 'paragraph';
            let level = null;
            if (/^h[1-6]$/.test(tag)) {
              kind = 'heading';
              level = Number(tag.slice(1));
            } else if (tag === 'li') {
              kind = 'listItem';
            } else if (tag === 'blockquote') {
              kind = 'quote';
            }
            const parts = [];
            appendInlineParts(element, kind, level, parts);
            if (parts.length) blocks.push(...parts);
          };

          const hasDirectText = (element) =>
            Array.from(element.childNodes || []).some(
              (node) => node.nodeType === Node.TEXT_NODE
                && (node.nodeValue || '').trim().length > 0
            );

          const hasSemanticDescendant = (element) =>
            Boolean(element.querySelector && element.querySelector(semanticSelector));

          const appendRichText = (element, blocks) => {
            const parts = [];
            appendInlineParts(element, 'richText', null, parts, element);
            if (parts.length) blocks.push(...parts);
          };

          const structuredBlocks = (root) => {
            const blocks = [];
            const visit = (element) => {
              if (blocks.length >= MAX_BLOCKS || isExcluded(element)) return;
              if (isCanonicalMathRoot(element)) {
                const source = mathSource(element);
                if (source) {
                  blocks.push({
                    kind: element.matches('.katex-display') ? 'mathBlock' : 'mathInline',
                    text: source,
                    level: null,
                    sourceElement: element
                  });
                }
                return;
              }
              if (element.matches && element.matches(semanticSelector)) {
                appendSemanticBlock(element, blocks);
                return;
              }
              if (element !== root
                  && hasDirectText(element)
                  && !hasSemanticDescendant(element)) {
                appendRichText(element, blocks);
                return;
              }
              element.childNodes.forEach((node) => {
                if (node.nodeType === Node.ELEMENT_NODE) visit(node);
              });
            };
            visit(root);
            if (blocks.length) return blocks.slice(0, MAX_BLOCKS);
            const fallback = textWithoutControls(root);
            return fallback ? [{
              kind: 'paragraph',
              text: fallback,
              level: null,
              sourceElement: root
            }] : [];
          };

          const postEmpty = (target, requestID) => {
            target.postMessage({
              version: 3,
              kind: "empty",
              requestID: requestID,
              documentToken: documentToken,
              responseID: null,
              blocks: []
            });
          };

          const postManualScroll = () => {
            const target = handler();
            if (!target) return;
            target.postMessage({
              version: 3,
              event: "manualScroll",
              documentToken: documentToken
            });
          };

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
            const root = document.documentElement;
            const likelyScrollbar = event.clientX >= root.clientWidth
              || event.clientY >= root.clientHeight;
            if (likelyScrollbar) postManualScroll();
          }, true);
          document.addEventListener('scroll', () => {
            // Scroll events generated by our own smooth scroll are deliberately
            // ignored. User intent is reported by trusted wheel/keyboard/
            // scrollbar input events above; no timer or position polling is used.
            if (performance.now() < programmaticScrollGuardUntil) return;
          }, true);

          globalThis.__floatTabsScrollToSpeechBlockV3 = (
            requestedDocumentToken,
            requestedResponseID,
            requestedBlockID
          ) => {
            if (requestedDocumentToken !== documentToken
                || typeof requestedResponseID !== 'string'
                || typeof requestedBlockID !== 'string') return false;
            const entry = locatorRegistry.get(requestedBlockID);
            if (!entry
                || entry.documentToken !== requestedDocumentToken
                || entry.responseID !== requestedResponseID) return false;
            if (!entry.element
                || !entry.element.isConnected
                || !isRendered(entry.element)) {
              locatorRegistry.delete(requestedBlockID);
              return false;
            }
            programmaticScrollGuardUntil = performance.now() + 1200;
            const reduceMotion = window.matchMedia
              && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
            entry.element.scrollIntoView({
              behavior: reduceMotion ? 'auto' : 'smooth',
              block: 'center',
              inline: 'nearest'
            });
            return true;
          };

          globalThis.__floatTabsChatGPTResponseRequestLatestV3 = (requestID) => {
            const target = handler();
            if (!target || typeof requestID !== 'string') return false;
            const roots = assistantRoots();
            const root = roots[roots.length - 1];
            if (!root) {
              postEmpty(target, requestID);
              return true;
            }
            const blocks = structuredBlocks(root);
            if (!blocks.length) {
              postEmpty(target, requestID);
              return true;
            }
            const responseID = responseIDFor(root);
            const previousBlockIDs = responseLocatorKeys.get(responseID);
            if (previousBlockIDs) {
              previousBlockIDs.forEach((blockID) => locatorRegistry.delete(blockID));
              responseLocatorKeys.delete(responseID);
            }
            const currentBlockIDs = new Set();
            const wireBlocks = blocks.map((block, index) => {
              const blockID = responseID + ':block-' + index;
              currentBlockIDs.add(blockID);
              locatorRegistry.set(blockID, {
                documentToken: documentToken,
                responseID: responseID,
                element: block.sourceElement
              });
              return {
                kind: block.kind,
                text: block.text,
                level: block.level,
                sourceLocator: {
                  documentToken: documentToken,
                  responseID: responseID,
                  blockID: blockID
                }
              };
            });
            responseLocatorKeys.set(responseID, currentBlockIDs);
            while (responseLocatorKeys.size > MAX_RESPONSE_GROUPS) {
              const oldestResponseID = responseLocatorKeys.keys().next().value;
              if (!oldestResponseID) break;
              const oldestBlockIDs = responseLocatorKeys.get(oldestResponseID);
              oldestBlockIDs?.forEach((blockID) => locatorRegistry.delete(blockID));
              responseLocatorKeys.delete(oldestResponseID);
            }
            target.postMessage({
              version: 3,
              kind: "response",
              requestID: requestID,
              documentToken: documentToken,
              responseID: responseID,
              blocks: wireBlocks
            });
            return true;
          };
        })();
        """
    }
}
