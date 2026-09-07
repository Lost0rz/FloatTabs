import Foundation
import WebKit

enum WebFocusTarget: String, CaseIterable, Codable, Equatable {
    case input
    case page
    case media
    case list
    case dialog
    case unavailable
}

enum WebFocusAdapterError: LocalizedError, Equatable {
    case inputUnavailable
    case pageUnavailable
    case unsupportedAction(String)
    case javascriptFailed(String)
    case noWebView

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "No usable input element was found."
        case .pageUnavailable:
            return "No usable page content element was found."
        case let .unsupportedAction(action):
            return "The adapter does not support \(action)."
        case let .javascriptFailed(message):
            return "Focus script failed: \(message)"
        case .noWebView:
            return "No active WebView is available."
        }
    }
}

struct WebFocusTransition: Equatable {
    let websiteIdentifier: String
    let from: WebFocusTarget
    let to: WebFocusTarget
    let succeeded: Bool
    let failureReason: String?
}

/// A website adapter owns only website-specific matching and candidate rules.
/// The protocol is deliberately async because candidate discovery happens in
/// the WebKit content process and must be repeated for every operation.
@MainActor
protocol WebSiteAdapter: AnyObject {
    var identifier: String { get }

    func matches(url: URL?, webView: WKWebView) async -> Bool
    func togglePrimaryFocus(in webView: WKWebView) async throws -> WebFocusTarget
    func focusInput(in webView: WKWebView) async throws
    func captureInputTargetForVoice(in webView: WKWebView) async throws -> Bool
    func focusInputForVoice(in webView: WKWebView) async throws
    func focusPage(in webView: WKWebView) async throws
    func currentFocus(in webView: WKWebView) async throws -> WebFocusTarget
    func focusNext(in webView: WKWebView) async throws
    func focusPrevious(in webView: WKWebView) async throws
}

extension WebSiteAdapter {
    func captureInputTargetForVoice(in webView: WKWebView) async throws -> Bool {
        false
    }

    func focusInputForVoice(in webView: WKWebView) async throws {
        try await focusInput(in: webView)
    }

    func focusNext(in webView: WKWebView) async throws {
        throw WebFocusAdapterError.unsupportedAction("nextItem")
    }

    func focusPrevious(in webView: WKWebView) async throws {
        throw WebFocusAdapterError.unsupportedAction("previousItem")
    }
}

/// Shared DOM semantics for the generic and ChatGPT adapters. It intentionally
/// avoids site-private class names and never assigns user content.
@MainActor
enum WebFocusDOM {
    static let commonFunctions = #"""
    const temporaryPageTabIndex = 'data-floattabs-focus-tabindex';
    const voiceInputTargetAttribute = 'data-floattabs-voice-target';
    const voiceInputSelectionProperty = '__floatTabsVoiceSelection';

    function isVisible(element) {
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none'
            && style.visibility !== 'hidden'
            && style.visibility !== 'collapse'
            && style.opacity !== '0'
            && rect.width > 0
            && rect.height > 0;
    }

    function isAriaHidden(element) {
        return !!element.closest('[aria-hidden="true"]');
    }

    function isInputElement(element) {
        if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
        const tag = element.tagName.toLowerCase();
        return tag === 'textarea'
            || element.isContentEditable === true
            || (element.hasAttribute('contenteditable')
                && element.getAttribute('contenteditable') !== 'false')
            || element.getAttribute('role') === 'textbox';
    }

    function isUsableInput(element) {
        if (!isInputElement(element)
            || !isVisible(element)
            || isAriaHidden(element)
            || element.matches(':disabled, [disabled], [inert]')) {
            return false;
        }
        return !element.readOnly;
    }

    function pageCandidate() {
        const candidates = Array.from(document.querySelectorAll(
            'main, [role="main"], article, body'
        ));
        return candidates.find(isVisible) || document.body || document.documentElement;
    }

    function isInMainRegion(element) {
        const main = pageCandidate();
        return !main || main === document.body || main === document.documentElement
            || main.contains(element);
    }

    function inputContext(element) {
        return [
            element.getAttribute('aria-label') || '',
            element.getAttribute('placeholder') || '',
            element.getAttribute('name') || '',
            element.getAttribute('id') || '',
            element.getAttribute('type') || '',
            element.textContent || ''
        ].join(' ').toLowerCase();
    }

    function isUtilityInput(element) {
        const context = inputContext(element);
        return element.getAttribute('type') === 'search'
            || /search|address|url|setting|find in page|navigate/.test(context);
    }

    function activeInputElement() {
        const active = document.activeElement;
        if (!active) return null;
        if (isInputElement(active)) return active;
        return active.closest?.(
            'textarea, [contenteditable]:not([contenteditable="false"]), [role="textbox"]'
        ) || null;
    }

    function isCurrentInput(element) {
        const activeInput = activeInputElement();
        return !!activeInput
            && (activeInput === element || element.contains(activeInput));
    }

    function clearCapturedVoiceInput() {
        document.querySelectorAll('[' + voiceInputTargetAttribute + ']').forEach((element) => {
            element.removeAttribute(voiceInputTargetAttribute);
            try { delete element[voiceInputSelectionProperty]; } catch (_) {}
        });
    }

    function captureInputSelection(element) {
        if (!element) return null;
        const tag = element.tagName.toLowerCase();
        if (tag === 'textarea' || tag === 'input') {
            return {
                kind: 'text',
                start: typeof element.selectionStart === 'number'
                    ? element.selectionStart
                    : null,
                end: typeof element.selectionEnd === 'number'
                    ? element.selectionEnd
                    : null,
                direction: element.selectionDirection || 'none'
            };
        }

        if (element.isContentEditable
            || (element.hasAttribute('contenteditable')
                && element.getAttribute('contenteditable') !== 'false')) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) return null;
            const range = selection.getRangeAt(0);
            if (!element.contains(range.startContainer)
                || !element.contains(range.endContainer)) {
                return null;
            }
            try {
                const startRange = document.createRange();
                startRange.selectNodeContents(element);
                startRange.setEnd(range.startContainer, range.startOffset);

                const endRange = document.createRange();
                endRange.selectNodeContents(element);
                endRange.setEnd(range.endContainer, range.endOffset);
                return {
                    kind: 'contenteditable',
                    start: startRange.toString().length,
                    end: endRange.toString().length
                };
            } catch (_) {
                return null;
            }
        }
        return null;
    }

    function textPointAtOffset(root, rawOffset) {
        const offset = Math.max(0, Number(rawOffset) || 0);
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let remaining = offset;
        let node = walker.nextNode();
        while (node) {
            const length = node.nodeValue ? node.nodeValue.length : 0;
            if (remaining <= length) {
                return { container: node, offset: remaining };
            }
            remaining -= length;
            node = walker.nextNode();
        }
        return { container: root, offset: root.childNodes.length };
    }

    function restoreInputSelection(element) {
        const snapshot = element?.[voiceInputSelectionProperty];
        if (!snapshot) {
            moveCaretToEnd(element);
            return;
        }

        const tag = element.tagName.toLowerCase();
        if ((tag === 'textarea' || tag === 'input')
            && typeof snapshot.start === 'number'
            && typeof snapshot.end === 'number') {
            try {
                element.setSelectionRange(
                    snapshot.start,
                    snapshot.end,
                    snapshot.direction || 'none'
                );
                return;
            } catch (_) {}
        }

        if (element.isContentEditable
            || (element.hasAttribute('contenteditable')
                && element.getAttribute('contenteditable') !== 'false')) {
            try {
                const start = textPointAtOffset(element, snapshot.start);
                const end = textPointAtOffset(element, snapshot.end);
                const range = document.createRange();
                range.setStart(start.container, start.offset);
                range.setEnd(end.container, end.offset);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
                return;
            } catch (_) {}
        }
        moveCaretToEnd(element);
    }

    function findInput(scoreInput) {
        const candidates = Array.from(document.querySelectorAll(
            'textarea, [contenteditable]:not([contenteditable="false"]), [role="textbox"]'
        ));
        let best = null;
        let bestScore = -Infinity;
        candidates.forEach((element, index) => {
            if (!isUsableInput(element)) return;
            const score = scoreInput(element) + (candidates.length - index) / 1000;
            if (score > bestScore) {
                best = element;
                bestScore = score;
            }
        });
        return best;
    }

    function focusWithoutScroll(element) {
        if (!element) return false;
        try {
            element.focus({ preventScroll: true });
        } catch (_) {
            element.focus();
        }
        return document.activeElement === element
            || element.contains(document.activeElement);
    }

    function moveCaretToEnd(element) {
        if (!element) return;
        const tag = element.tagName.toLowerCase();
        if (tag === 'textarea' || tag === 'input') {
            const end = typeof element.value === 'string' ? element.value.length : 0;
            try { element.setSelectionRange(end, end); } catch (_) {}
            return;
        }
        if (element.isContentEditable
            || (element.hasAttribute('contenteditable')
                && element.getAttribute('contenteditable') !== 'false')) {
            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(element);
            range.collapse(false);
            selection.removeAllRanges();
            selection.addRange(range);
        }
    }

    function cleanupTemporaryPageTabIndex() {
        document.querySelectorAll('[' + temporaryPageTabIndex + ']').forEach((element) => {
            element.removeAttribute('tabindex');
            element.removeAttribute(temporaryPageTabIndex);
        });
    }

    function focusInputElement(element, preserveCaret = false) {
        cleanupTemporaryPageTabIndex();
        if (!focusWithoutScroll(element)) return false;
        if (preserveCaret) {
            restoreInputSelection(element);
        } else {
            moveCaretToEnd(element);
        }
        return true;
    }

    function focusPageElement(element) {
        if (!element) return false;
        cleanupTemporaryPageTabIndex();

        // A page candidate such as <main> can contain the composer. Blur the
        // current editor first so a failed/partial focus request cannot leave
        // the caret in the input while reporting a successful page switch.
        const active = document.activeElement;
        if (isInputElement(active)) {
            active.blur();
        }
        const selection = window.getSelection();
        if (selection) selection.removeAllRanges();

        if (!element.hasAttribute('tabindex')) {
            element.setAttribute('tabindex', '-1');
            element.setAttribute(temporaryPageTabIndex, 'true');
        }
        if (!focusWithoutScroll(element)) return false;

        // Do not accept a descendant input as proof that the page received
        // focus. This exact check is important for containers such as <main>.
        return document.activeElement === element
            && !isInputElement(document.activeElement);
    }

    function currentTarget() {
        const activeInput = activeInputElement();
        if (isUsableInput(activeInput) && !isUtilityInput(activeInput)) {
            return 'input';
        }
        return pageCandidate() ? 'page' : 'unavailable';
    }

    function result(success, target, reason) {
        return { success: !!success, target: target || 'unavailable', reason: reason || null };
    }
    """#

    static func inputFocusScript(scoring: String) -> String {
        inputFocusScript(scoring: scoring, preservingCapturedTarget: false)
    }

    static func inputFocusScript(
        scoring: String,
        preservingCapturedTarget: Bool
    ) -> String {
        """
        (() => {
            \(commonFunctions)

            const preserveCapturedTarget = \(preservingCapturedTarget ? "true" : "false");
            if (preserveCapturedTarget) {
                // The marker was placed before AppKit/WebKit activation. Do
                // not trust the post-activation document.activeElement: WebKit
                // can restore a different editor from its own history.
                const captured = document.querySelector(
                    '[' + voiceInputTargetAttribute + '="true"]'
                );
                if (isUsableInput(captured) && !isUtilityInput(captured)) {
                    const capturedSuccess = focusInputElement(captured, true);
                    clearCapturedVoiceInput();
                    if (capturedSuccess) return result(true, 'input', null);
                }
                clearCapturedVoiceInput();
            }

            // The active composer is the common fast path for voice input,
            // including ChatGPT's message editor. Reusing it avoids a second
            // WebKit round trip just to ask where focus currently is, and it
            // prevents a focused edit box from being replaced by the bottom
            // composer while the user is dictating an existing message.
            const active = activeInputElement();
            if (isUsableInput(active) && !isUtilityInput(active)) {
                const activeSuccess = focusInputElement(active);
                if (activeSuccess) return result(true, 'input', null);
            }

            const input = findInput((element) => \(scoring));
            if (!input) return result(false, 'unavailable', 'input_unavailable');
            const success = focusInputElement(input);
            return result(success, success ? 'input' : 'unavailable', success ? null : 'focus_failed');
        })()
        """
    }

    static func captureInputTargetForVoiceScript() -> String {
        """
        (() => {
            \(commonFunctions)
            clearCapturedVoiceInput();
            const active = activeInputElement();
            if (!isUsableInput(active) || isUtilityInput(active)) {
                return { captured: false };
            }
            active.setAttribute(voiceInputTargetAttribute, 'true');
            try {
                active[voiceInputSelectionProperty] = captureInputSelection(active);
            } catch (_) {}
            return { captured: true };
        })()
        """
    }

    static func pageFocusScript() -> String {
        """
        (() => {
            \(commonFunctions)
            const page = pageCandidate();
            if (!page) return result(false, 'unavailable', 'page_unavailable');
            const success = focusPageElement(page);
            return result(success, success ? 'page' : 'unavailable', success ? null : 'focus_failed');
        })()
        """
    }

    static func currentFocusScript() -> String {
        """
        (() => {
            \(commonFunctions)
            return { target: currentTarget() };
        })()
        """
    }

    static func inputAvailabilityScript(scoring: String) -> String {
        """
        (() => {
            \(commonFunctions)
            return { available: !!findInput((element) => \(scoring)) };
        })()
        """
    }

    static func evaluate(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value ?? NSNull())
                }
            }
        }
        guard let dictionary = value as? [String: Any] else {
            throw WebFocusAdapterError.javascriptFailed("The page returned an unexpected value.")
        }
        return dictionary
    }

    static func resultTarget(from dictionary: [String: Any]) -> WebFocusTarget {
        guard let raw = dictionary["target"] as? String else { return .unavailable }
        return WebFocusTarget(rawValue: raw) ?? .unavailable
    }

    static func succeeded(_ dictionary: [String: Any]) -> Bool {
        (dictionary["success"] as? Bool) ?? false
    }

    static func reason(from dictionary: [String: Any]) -> String? {
        dictionary["reason"] as? String
    }
}
