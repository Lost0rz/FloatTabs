import Foundation
import WebKit

/// Swift-owned protocol model for the independent one-shot ChatGPT response
/// bridge. It contains only structured response blocks in transient memory.
enum ChatGPTResponseMessageKind: String, Equatable, Sendable {
    case response
    case empty
}

struct ChatGPTResponsePayload: Equatable, Sendable {
    static let currentVersion = 1
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
            let parsedBlocks = rawBlocks.compactMap(parseBlock)
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

    private static func parseBlock(_ body: [String: Any]) -> SpeechContentBlock? {
        guard let rawKind = body["kind"] as? String,
              let kind = SpeechContentBlockKind(rawValue: rawKind),
              let text = body["text"] as? String,
              !text.isEmpty else {
            return nil
        }
        let level = (body["level"] as? NSNumber)?.intValue
        return SpeechContentBlock(kind: kind, text: text, level: level)
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
          let nextOpaqueKey = 0;
          const MAX_BLOCKS = 256;
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

          const structuredBlocks = (root) => {
            const selectors = 'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table';
            const nodes = [];
            if (root.matches && root.matches(selectors)) nodes.push(root);
            nodes.push(...root.querySelectorAll(selectors));
            const blocks = [];
            nodes.forEach((element) => {
              if (blocks.length >= MAX_BLOCKS) return;
              if (element.closest('script,style,noscript,button,svg,[aria-hidden="true"]')) return;
              const nestedBlock = element.parentElement?.closest(selectors);
              if (nestedBlock && nestedBlock !== element) return;
              const text = normalizedText(element);
              if (!text) return;
              const tag = element.tagName.toLowerCase();
              let kind = 'paragraph';
              let level = null;
              if (/^h[1-6]$/.test(tag)) {
                kind = 'heading';
                level = Number(tag.slice(1));
              } else if (tag === 'li') {
                kind = 'listItem';
              } else if (tag === 'blockquote') {
                kind = 'quote';
              } else if (tag === 'pre') {
                kind = 'code';
              } else if (tag === 'table') {
                kind = 'table';
              }
              blocks.push({ kind: kind, text: text, level: level });
            });

            if (blocks.length) return blocks;
            const fallback = normalizedText(root);
            return fallback ? [{ kind: 'paragraph', text: fallback, level: null }] : [];
          };

          globalThis.__floatTabsChatGPTResponseRequestLatestV1 = (requestID) => {
            const target = handler();
            if (!target || typeof requestID !== 'string') return false;
            const roots = assistantRoots();
            const root = roots[roots.length - 1];
            if (!root) {
              target.postMessage({
                version: 1,
                kind: "empty",
                requestID: requestID,
                documentToken: documentToken,
                responseID: null,
                blocks: []
              });
              return true;
            }
            const blocks = structuredBlocks(root);
            if (!blocks.length) {
              target.postMessage({
                version: 1,
                kind: "empty",
                requestID: requestID,
                documentToken: documentToken,
                responseID: null,
                blocks: []
              });
              return true;
            }
            target.postMessage({
              version: 1,
              kind: "response",
              requestID: requestID,
              documentToken: documentToken,
              responseID: responseIDFor(root),
              blocks: blocks
            });
            return true;
          };
        })();
        """
    }
}
