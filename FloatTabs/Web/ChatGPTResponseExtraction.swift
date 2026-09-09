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
          // Keep extraction bounded without dropping ordinary long replies.
          // The coordinator owns the smaller playback window and drains the
          // remainder incrementally.
          const MAX_BLOCKS = 1024;
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
          const mathSelector =
            'math,.katex-display,.katex,mjx-container,' +
            '[data-math],[data-latex],[data-tex],[role="math"]';
          const excludedSelector =
            'script,style,noscript,button,[role="button"],[role="toolbar"],toolbar,' +
            '[aria-hidden="true"],svg,[data-testid*="action"],[data-testid*="toolbar"]';

          const isExcluded = (element) => {
            if (!element || !element.closest) return false;
            const excluded = element.closest(excludedSelector);
            if (!excluded) return false;
            // Rendered semantic math may wrap an aria-hidden visual branch.
            // Let the canonical math root own that subtree instead of losing
            // the formula to the visual-only exclusion rule.
            return !isCanonicalMathRoot(excluded);
          };

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
            if (element.matches('[data-math],[data-latex],[data-tex],[role="math"]')) {
              const ancestor = element.parentElement?.closest(mathSelector);
              if (ancestor && ancestor !== element && isRendered(ancestor)) return false;
            }
            return true;
          };

          const mathKind = (element) =>
            element.matches('.katex-display')
              || window.getComputedStyle(element).display === 'block'
              ? 'mathBlock'
              : 'mathInline';

          // Recover only a bounded, common MathML subset when ChatGPT does
          // not expose TeX annotation/data attributes. This is structural
          // parsing, not MathML.textContent flattening: superscripts,
          // subscripts, fractions, roots, and fenced groups retain their
          // semantic shape for the local speech normalizer.
          const semanticMathMLSource = (element) => {
            const math = element.matches && element.matches('math')
              ? element
              : element.querySelector && element.querySelector('math');
            if (!math) return null;

            const children = (node) => Array.from(node.children || [])
              .map(render)
              .filter(Boolean)
              .join(' ')
              .trim();
            const compactLabel = (value) => (value || '')
              .replace(/\\s+/g, '')
              .trim();
            const render = (node) => {
              if (!node || node.nodeType !== Node.ELEMENT_NODE) return '';
              const tag = node.tagName.toLowerCase();
              if (tag === 'semantics') {
                const semanticChild = Array.from(node.children || [])
                  .find((child) => !['annotation', 'annotation-xml'].includes(
                    child.tagName.toLowerCase()
                  ));
                return semanticChild ? render(semanticChild) : '';
              }
              if (tag === 'annotation' || tag === 'annotation-xml') return '';
              if (['mi', 'mn', 'mo', 'mtext'].includes(tag)) {
                return (node.textContent || '').replace(/\\s+/g, ' ').trim();
              }
              if (tag === 'msup') {
                const values = Array.from(node.children || []).map(render);
                return values.length >= 2 ? values[0] + '^{' + values[1] + '}' : '';
              }
              if (tag === 'msub') {
                const values = Array.from(node.children || []).map(render);
                return values.length >= 2
                  ? values[0] + '_{' + compactLabel(values[1]) + '}'
                  : '';
              }
              if (tag === 'msubsup') {
                const values = Array.from(node.children || []).map(render);
                return values.length >= 3
                  ? values[0] + '_{' + compactLabel(values[1]) + '}^{' + values[2] + '}'
                  : '';
              }
              if (tag === 'mfrac') {
                const values = Array.from(node.children || []).map(render);
                return values.length >= 2
                  ? '(' + values[0] + ') / (' + values[1] + ')'
                  : '';
              }
              if (tag === 'msqrt') {
                return '√(' + children(node) + ')';
              }
              if (tag === 'mfenced') {
                const open = node.getAttribute('open') || '(';
                const close = node.getAttribute('close') || ')';
                return open + children(node) + close;
              }
              return children(node);
            };

            const source = render(math).replace(/\\s+/g, ' ').trim();
            return source || null;
          };

          const mathSource = (element) => {
            const annotation = Array.from(element.querySelectorAll('annotation'))
              .find((node) => (node.getAttribute('encoding') || '')
                .toLowerCase().includes('tex'));
            const dataSource = element.getAttribute('data-latex')
              || element.getAttribute('data-tex')
              || element.querySelector('[data-latex]')?.getAttribute('data-latex')
              || element.querySelector('[data-tex]')?.getAttribute('data-tex');
            const ariaSource = element.getAttribute('aria-label')
              || element.getAttribute('alttext')
              || element.querySelector('[aria-label]')?.getAttribute('aria-label');
            const semanticSource = semanticMathMLSource(element);
            const candidate = annotation?.textContent
              || dataSource
              || semanticSource
              || ariaSource
              || textWithoutControls(element);
            const normalized = (candidate || '').replace(/\\s+/g, ' ').trim();
            return (normalized || '__floatTabs_formula_without_semantic_source__')
              .slice(0, MAX_BLOCK_TEXT);
          };

          const splitBoundedText = (value) => {
            const pieces = [];
            let remainder = (value || '').replace(/\\s+/g, ' ').trim();
            while (remainder.length > MAX_BLOCK_TEXT) {
              const window = remainder.slice(0, MAX_BLOCK_TEXT);
              const splitAt = Math.max(window.lastIndexOf(' '), window.lastIndexOf('\\t'));
              const boundary = splitAt > 0 ? splitAt : MAX_BLOCK_TEXT;
              const piece = remainder.slice(0, boundary).trim();
              if (piece) pieces.push(piece);
              remainder = remainder.slice(boundary).trim();
            }
            if (remainder) pieces.push(remainder);
            return pieces;
          };

          const appendTextPart = (parts, kind, text, level, sourceElement) => {
            const value = (text || '').replace(/\\s+/g, ' ').trim();
            if (!value) return;
            const previous = parts[parts.length - 1];
            if (previous && previous.kind === kind && previous.level === level) {
              parts.pop();
              splitBoundedText((previous.text + ' ' + value).trim()).forEach((piece) => {
                parts.push({
                  kind: kind,
                  text: piece,
                  level: level,
                  sourceElement: sourceElement
                });
              });
            } else {
              splitBoundedText(value).forEach((piece) => {
                parts.push({
                  kind: kind,
                  text: piece,
                  level: level,
                  sourceElement: sourceElement
                });
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
              if (isCanonicalMathRoot(node)) {
                const source = mathSource(node);
                parts.push({
                  kind: mathKind(node),
                  text: source,
                  level: null,
                  sourceElement: node
                });
                return;
              }
              if (isExcluded(node)) return;
              if (node.matches && node.matches(mathSelector)) {
                return;
              }
              appendInlineParts(node, kind, level, parts, sourceElement);
            });
          };

          const appendSemanticBlock = (element, blocks) => {
            const tag = element.tagName.toLowerCase();
            if (tag === 'pre' || tag === 'table') {
              splitBoundedText(textWithoutControls(element)).forEach((text) => {
                blocks.push({
                  kind: tag === 'pre' ? 'code' : 'table',
                  text: text,
                  level: null,
                  sourceElement: element
                });
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
              if (blocks.length >= MAX_BLOCKS) return;
              if (isCanonicalMathRoot(element)) {
                const source = mathSource(element);
                blocks.push({
                  kind: mathKind(element),
                  text: source,
                  level: null,
                  sourceElement: element
                });
                return;
              }
              if (isExcluded(element)) return;
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
            return splitBoundedText(fallback).map((text) => ({
              kind: 'paragraph',
              text: text,
              level: null,
              sourceElement: root
            }));
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
