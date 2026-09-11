import Foundation
import WebKit

enum CalibreReaderKind: String, Equatable, Sendable {
    case epub
    case kepub
}

enum CalibreReaderRouteMatcher {
    /// Calibre-Web's reader route is identified from the tail only. The
    /// committed origin remains an identity field, never a hostname allowlist.
    static func readerKind(for url: URL?) -> CalibreReaderKind? {
        guard let url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        let components = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let readIndex = components.lastIndex(where: {
            $0.caseInsensitiveCompare("read") == .orderedSame
        }),
        readIndex + 2 == components.count - 1,
        Int(components[readIndex + 1]) != nil else {
            return nil
        }
        switch components[readIndex + 2].lowercased() {
        case "epub": return .epub
        case "kepub": return .kepub
        default: return nil
        }
    }

    static func committedOrigin(for url: URL) -> URL? {
        guard let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme.lowercased()
        components.host = host.lowercased()
        components.port = url.port
        return components.url
    }
}

struct CalibreReaderDocumentIdentity: Equatable, Sendable {
    let slotID: UUID
    let documentGeneration: UInt64
    let committedURL: URL
    let origin: URL
    let readerKind: CalibreReaderKind
}

struct CalibreReadingUnitIdentity: Equatable, Sendable {
    let document: CalibreReaderDocumentIdentity
    let startCFI: String
    let endCFI: String
}

struct CalibreReaderPage: Equatable, Sendable {
    let identity: CalibreReadingUnitIdentity
    let text: String
    let isAtEnd: Bool
}

struct CalibreReaderRelocation: Equatable, Sendable {
    let identity: CalibreReadingUnitIdentity
    let transitionToken: UInt64?
}

enum CalibreReaderBridgeError: Error, Equatable {
    case invalidCandidate
    case runtimeUnavailable
    case staleDocument
    case staleWebView
    case emptyLocation
    case emptyText
    case javascriptFailed
}

@MainActor
protocol CalibreReaderAccess: AnyObject {
    var slotID: UUID { get }
    var currentDocumentIdentity: CalibreReaderDocumentIdentity? { get }
    var isReaderCandidate: Bool { get }
    var onRelocation: ((CalibreReaderRelocation) -> Void)? { get set }

    func detectCurrentReader(completion: @escaping (Bool) -> Void)
    func extractCurrentReadingUnit(
        completion: @escaping (Result<CalibreReaderPage, Error>) -> Void
    )
    func requestAdvance(
        from identity: CalibreReadingUnitIdentity,
        transitionToken: UInt64,
        completion: @escaping (Bool) -> Void
    )
    func cancelPendingWork()
}

/// Page-world bridge for the Calibre-Web EPUB reader. The bridge only calls
/// the reader runtime after both the committed route tail and the runtime
/// signature have been validated. It never falls back to document/spine text.
@MainActor
final class CalibreReaderBridge: NSObject, WKScriptMessageHandler, CalibreReaderAccess {
    typealias PageCompletion = (Result<CalibreReaderPage, Error>) -> Void

    static let messageHandlerName = "floatTabsCalibreReader"
    static let contentWorld = WKContentWorld.page

    let slotID: UUID
    private let onRuntimeReset: @MainActor (UUID) -> Void
    private let onCandidateChange: @MainActor (UUID) -> Void
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var documentGeneration: UInt64 = 0
    private(set) var currentDocumentIdentity: CalibreReaderDocumentIdentity?
    private var runtimeReady = false
    private var readinessObserverGeneration: UInt64?
    private var pendingExtractions: [UUID: PageCompletion] = [:]
    private var pendingAdvance: (
        identity: CalibreReadingUnitIdentity,
        transitionToken: UInt64,
        completion: (Bool) -> Void
    )?
    private(set) var isInvalidated = false
    var onRelocation: ((CalibreReaderRelocation) -> Void)?

    var isReaderCandidate: Bool {
        currentDocumentIdentity != nil && runtimeReady
    }

    init(
        slotID: UUID,
        onRuntimeReset: @escaping @MainActor (UUID) -> Void = { _ in },
        onCandidateChange: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.slotID = slotID
        self.onRuntimeReset = onRuntimeReset
        self.onCandidateChange = onCandidateChange
        super.init()
    }

    func install(into userContentController: WKUserContentController) {
        guard !isInvalidated else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.documentStartMarkerScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.contentWorld
            )
        )
        userContentController.add(
            self,
            contentWorld: Self.contentWorld,
            name: Self.messageHandlerName
        )
        self.userContentController = userContentController
    }

    func attach(to webView: WKWebView) {
        guard !isInvalidated else { return }
        self.webView = webView
    }

    /// A commit creates a new document identity even when the URL is reused
    /// by a reload. Every extraction and relocation operation must match this
    /// generation and the exact WebView instance.
    func handleNavigationCommit(_ committedURL: URL?) {
        documentGeneration &+= 1
        runtimeReady = false
        readinessObserverGeneration = nil
        currentDocumentIdentity = Self.documentIdentity(
            slotID: slotID,
            generation: documentGeneration,
            url: committedURL
        )
        cancelPendingWork()
        onRuntimeReset(slotID)
        onCandidateChange(slotID)
        guard currentDocumentIdentity != nil else { return }
        detectCurrentReader()
    }

    func handleNavigationFinish(_ committedURL: URL?) {
        guard let committedURL,
              let currentDocumentIdentity,
              currentDocumentIdentity.committedURL == committedURL else {
            return
        }
        detectCurrentReader()
    }

    func detectCurrentReader(completion: @escaping (Bool) -> Void = { _ in }) {
        guard !isInvalidated,
              currentDocumentIdentity != nil,
              CalibreReaderRouteMatcher.readerKind(
                  for: currentDocumentIdentity?.committedURL
              ) != nil,
              let webView else {
            runtimeReady = false
            completion(false)
            return
        }
        let expectedDocument = currentDocumentIdentity
        evaluate(Self.runtimeDetectionScript, in: webView) { [weak self, weak webView] value, error in
            guard let self else {
                completion(false)
                return
            }
            guard let webView,
                  let expectedDocument,
                  self.isCurrent(expectedDocument: expectedDocument, webView: webView) else {
                completion(false)
                return
            }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["valid"] as? Bool == true,
                  result["kind"] as? String == expectedDocument.readerKind.rawValue else {
                self.runtimeReady = false
                if let result = value as? [String: Any],
                   result["readinessPending"] as? Bool == true {
                    self.installReaderReadinessObserver(
                        expectedDocument: expectedDocument,
                        webView: webView
                    )
                }
                self.onCandidateChange(self.slotID)
                completion(false)
                return
            }
            self.runtimeReady = true
            self.readinessObserverGeneration = nil
            self.installRelocationObserver(
                expectedDocument: expectedDocument,
                webView: webView
            )
            self.onCandidateChange(self.slotID)
            completion(true)
        }
    }

    func extractCurrentReadingUnit(completion: @escaping PageCompletion) {
        guard !isInvalidated,
              isReaderCandidate,
              let expectedDocument = currentDocumentIdentity,
              let webView else {
            completion(.failure(
                currentDocumentIdentity == nil
                    ? CalibreReaderBridgeError.invalidCandidate
                    : CalibreReaderBridgeError.runtimeUnavailable
            ))
            return
        }

        let requestID = UUID()
        pendingExtractions[requestID] = completion
        evaluate(Self.currentReadingUnitScript, in: webView) { [weak self, weak webView] value, error in
            guard let self,
                  let pending = self.pendingExtractions.removeValue(forKey: requestID),
                  let webView,
                  self.isCurrent(expectedDocument: expectedDocument, webView: webView) else {
                return
            }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["valid"] as? Bool == true,
                  let startCFI = result["startCFI"] as? String,
                  let endCFI = result["endCFI"] as? String,
                  !startCFI.isEmpty,
                  !endCFI.isEmpty else {
                pending(.failure(error == nil
                    ? CalibreReaderBridgeError.emptyLocation
                    : CalibreReaderBridgeError.javascriptFailed))
                return
            }
            let page = CalibreReaderPage(
                identity: CalibreReadingUnitIdentity(
                    document: expectedDocument,
                    startCFI: startCFI,
                    endCFI: endCFI
                ),
                text: result["text"] as? String ?? "",
                isAtEnd: result["atEnd"] as? Bool ?? false
            )
            pending(.success(page))
        }
    }

    func requestAdvance(
        from identity: CalibreReadingUnitIdentity,
        transitionToken: UInt64,
        completion: @escaping (Bool) -> Void
    ) {
        guard !isInvalidated,
              isReaderCandidate,
              let expectedDocument = currentDocumentIdentity,
              identity.document == expectedDocument,
              let webView else {
            completion(false)
            return
        }
        guard pendingAdvance == nil else {
            completion(false)
            return
        }
        pendingAdvance = (identity, transitionToken, completion)
        evaluate(
            Self.advanceScript(
                startCFI: identity.startCFI,
                endCFI: identity.endCFI,
                generation: expectedDocument.documentGeneration,
                transitionToken: transitionToken
            ),
            in: webView
        ) { [weak self, weak webView] value, error in
            guard let self,
                  let webView,
                  let pending = self.pendingAdvance,
                  self.isCurrent(expectedDocument: expectedDocument, webView: webView) else {
                return
            }
            guard error == nil,
                  let result = value as? [String: Any],
                  result["valid"] as? Bool == true,
                  result["requested"] as? Bool == true else {
                self.pendingAdvance = nil
                pending.completion(false)
                return
            }
            // The callback confirms only that rendition.next() was invoked.
            // Completion of the transition is delivered exclusively by the
            // real rendition "relocated" event below.
            pending.completion(true)
        }
    }

    func cancelPendingWork() {
        let extractions = pendingExtractions.values
        pendingExtractions.removeAll()
        extractions.forEach { $0(.failure(CalibreReaderBridgeError.staleDocument)) }
        if let pendingAdvance {
            self.pendingAdvance = nil
            pendingAdvance.completion(false)
        }
    }

    func handleRuntimeReplacement() {
        documentGeneration &+= 1
        runtimeReady = false
        readinessObserverGeneration = nil
        currentDocumentIdentity = nil
        cancelPendingWork()
        onRuntimeReset(slotID)
        onCandidateChange(slotID)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        cancelPendingWork()
        currentDocumentIdentity = nil
        runtimeReady = false
        readinessObserverGeneration = nil
        userContentController?.removeScriptMessageHandler(
            forName: Self.messageHandlerName,
            contentWorld: Self.contentWorld
        )
        userContentController = nil
        webView = nil
        onRuntimeReset(slotID)
        onCandidateChange(slotID)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let (document, body) = validatedPageMessage(message) else {
            return
        }

        switch body["event"] as? String {
        case "readerReady":
            guard readinessObserverGeneration == document.documentGeneration else {
                return
            }
            readinessObserverGeneration = nil
            detectCurrentReader()
        case "advanceFailed":
            guard let pendingAdvance,
                  let eventToken = body["transitionToken"] as? NSNumber,
                  eventToken.uint64Value == pendingAdvance.transitionToken else {
                return
            }
            self.pendingAdvance = nil
            pendingAdvance.completion(false)
        case "relocated":
            handleRelocatedMessage(body, document: document)
        default:
            return
        }
    }

    private func validatedPageMessage(
        _ message: WKScriptMessage
    ) -> (CalibreReaderDocumentIdentity, [String: Any])? {
        guard !isInvalidated,
              let attachedWebView = webView,
              let document = currentDocumentIdentity,
              Self.pageMessagePassesSecurityContract(
                  messageWebView: message.webView,
                  attachedWebView: attachedWebView,
                  isMainFrame: message.frameInfo.isMainFrame,
                  originScheme: message.frameInfo.securityOrigin.protocol,
                  originHost: message.frameInfo.securityOrigin.host,
                  originPort: message.frameInfo.securityOrigin.port,
                  documentOrigin: document.origin
              ),
              let body = message.body as? [String: Any],
              let eventGeneration = body["generation"] as? NSNumber,
              eventGeneration.uint64Value == document.documentGeneration else {
            return nil
        }
        return (document, body)
    }

    private func handleRelocatedMessage(
        _ body: [String: Any],
        document: CalibreReaderDocumentIdentity
    ) {
        guard let startCFI = body["startCFI"] as? String,
              let endCFI = body["endCFI"] as? String,
              !startCFI.isEmpty,
              !endCFI.isEmpty else {
            return
        }

        let identity = CalibreReadingUnitIdentity(
            document: document,
            startCFI: startCFI,
            endCFI: endCFI
        )
        if let pendingAdvance {
            guard pendingAdvance.identity != identity else {
                // The reader acknowledged the old location again. It is not
                // a completed transition, so keep waiting for a changed CFI.
                return
            }
            self.pendingAdvance = nil
            pendingAdvance.completion(true)
            onRelocation?(CalibreReaderRelocation(
                identity: identity,
                transitionToken: pendingAdvance.transitionToken
            ))
            return
        }
        onRelocation?(CalibreReaderRelocation(identity: identity, transitionToken: nil))
    }

    // MARK: Pinned Calibre-Web reader scripts

    static let documentStartMarkerScript = """
    (() => {
        window.__floatTabsCalibreReaderBridgeInstalled = true;
    })();
    """

    static let runtimeDetectionScript = """
    (() => {
        const reader = window.reader;
        const rendition = reader && reader.rendition;
        const book = reader && reader.book;
        const opened = book && book.opened;
        const location = rendition && typeof rendition.currentLocation === 'function';
        const next = rendition && typeof rendition.next === 'function';
        const on = rendition && typeof rendition.on === 'function';
        const pathParts = String(window.location && window.location.pathname || '')
            .split('/').filter(Boolean);
        const routeKind = pathParts.length ? pathParts[pathParts.length - 1].toLowerCase() : '';
        const bookUrlKind = (window.calibre && String(window.calibre.bookUrl || '')
            .toLowerCase().includes('kepub')) ? 'kepub' : 'epub';
        const kind = routeKind === 'kepub' || routeKind === 'epub' ? routeKind : bookUrlKind;
        return {
            valid: !!(reader && book && book.package && rendition && location && next && on),
            readinessPending: !!(reader && book && !book.package
                && opened && typeof opened.then === 'function'),
            kind: kind
        };
    })()
    """

    static func readerReadinessObserverScript(generation: UInt64) -> String {
        let generation = String(generation)
        let handler = Self.jsonString(Self.messageHandlerName)
        return """
        (() => {
            const reader = window.reader;
            const book = reader && reader.book;
            const opened = book && book.opened;
            if (!book || !opened || typeof opened.then !== 'function') return false;
            const marker = '__floatTabsCalibreReaderReadinessGeneration';
            if (window[marker] === (\(generation))) return true;
            window[marker] = (\(generation));
            opened.then(
                () => {
                    const handler = window.webkit && window.webkit.messageHandlers[\(handler)];
                    if (!handler) return;
                    handler.postMessage({
                        event: 'readerReady',
                        generation: \(generation)
                    });
                },
                () => {}
            );
            return true;
        })()
        """
    }

    static let currentReadingUnitScript = """
    (() => {
        const reader = window.reader;
        const rendition = reader && reader.rendition;
        if (!reader || !reader.book || !rendition || typeof rendition.currentLocation !== 'function') {
            return { valid: false };
        }
        const location = rendition.currentLocation();
        const startCFI = location && location.start && location.start.cfi;
        const endCFI = location && location.end && location.end.cfi;
        if (!startCFI || !endCFI) return { valid: false };

        const contents = [];
        if (typeof rendition.getContents === 'function') {
            const currentContents = rendition.getContents() || [];
            currentContents.forEach((content) => contents.push(content));
        }
        const views = rendition.manager && rendition.manager.views;
        const viewItems = views && Array.isArray(views.views) ? views.views : [];
        viewItems.forEach((view) => contents.push(view));
        if (reader.book.renderer) contents.push(reader.book.renderer);

        const documents = contents.map((content) => {
            if (!content) return null;
            return content.document || content.contentDocument || content.doc || null;
        }).filter((document, index, all) => document && all.indexOf(document) === index);

        function cfiRange(cfi, document) {
            try {
                const parser = new ePub.CFI(cfi);
                if (typeof parser.toRange === 'function') return parser.toRange(document);
                if (typeof parser.getRange === 'function') return parser.getRange(document);
            } catch (_) {}
            return null;
        }

        function find(cfi) {
            for (const document of documents) {
                const range = cfiRange(cfi, document);
                if (range) return { document, range };
            }
            return null;
        }

        const start = find(startCFI);
        const end = find(endCFI);
        if (!start || !end) return { valid: false };

        let text = '';
        if (start.document === end.document) {
            const range = start.document.createRange();
            range.setStart(start.range.startContainer, start.range.startOffset);
            range.setEnd(end.range.endContainer, end.range.endOffset);
            text = range.toString();
        } else {
            const startRange = start.document.createRange();
            startRange.setStart(start.range.startContainer, start.range.startOffset);
            startRange.selectNodeContents(start.document.body);
            startRange.setStart(start.range.startContainer, start.range.startOffset);
            text += startRange.toString();
            const endRange = end.document.createRange();
            endRange.selectNodeContents(end.document.body);
            endRange.setEnd(end.range.endContainer, end.range.endOffset);
            text += endRange.toString();
        }
        return {
            valid: true,
            startCFI: String(startCFI),
            endCFI: String(endCFI),
            text: text,
            atEnd: !!location.atEnd
        };
    })()
    """

    static func advanceScript(
        startCFI: String,
        endCFI: String,
        generation: UInt64 = 0,
        transitionToken: UInt64 = 0
    ) -> String {
        let start = Self.jsonString(startCFI)
        let end = Self.jsonString(endCFI)
        let generation = String(generation)
        let transitionToken = String(transitionToken)
        let handler = Self.jsonString(Self.messageHandlerName)
        return """
        (() => {
            const reader = window.reader;
            const rendition = reader && reader.rendition;
            if (!reader || !reader.book || !rendition
                || typeof rendition.currentLocation !== 'function'
                || typeof rendition.next !== 'function') {
                return { valid: false, requested: false };
            }
            const location = rendition.currentLocation();
            const currentStart = location && location.start && location.start.cfi;
            const currentEnd = location && location.end && location.end.cfi;
            if (currentStart !== (\(start)) || currentEnd !== (\(end))) {
                return { valid: false, requested: false };
            }
            try {
                const result = rendition.next();
                if (result && typeof result.then === 'function') {
                    result.then(
                        () => {},
                        () => {
                            const handler = window.webkit && window.webkit.messageHandlers[\(handler)];
                            if (!handler) return;
                            handler.postMessage({
                                event: 'advanceFailed',
                                generation: \(generation),
                                transitionToken: \(transitionToken)
                            });
                        }
                    );
                }
                return { valid: true, requested: true };
            } catch (_) {
                return { valid: false, requested: false };
            }
        })()
        """
    }

    private static func jsonString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private func installRelocationObserver(
        expectedDocument: CalibreReaderDocumentIdentity,
        webView: WKWebView
    ) {
        evaluate(
            Self.relocationObserverScript(
                generation: expectedDocument.documentGeneration
            ),
            in: webView
        ) { _, _ in }
    }

    private func installReaderReadinessObserver(
        expectedDocument: CalibreReaderDocumentIdentity,
        webView: WKWebView
    ) {
        guard readinessObserverGeneration != expectedDocument.documentGeneration else {
            return
        }
        readinessObserverGeneration = expectedDocument.documentGeneration
        evaluate(
            Self.readerReadinessObserverScript(
                generation: expectedDocument.documentGeneration
            ),
            in: webView
        ) { [weak self, weak webView] value, _ in
            guard let self,
                  let webView,
                  self.isCurrent(expectedDocument: expectedDocument, webView: webView),
                  (value as? Bool) == true else {
                return
            }
        }
    }

    static func relocationObserverScript(generation: UInt64) -> String {
        let generation = String(generation)
        let handler = Self.jsonString(Self.messageHandlerName)
        return """
        (() => {
            const reader = window.reader;
            const rendition = reader && reader.rendition;
            if (!rendition || typeof rendition.on !== 'function') return false;
            const marker = '__floatTabsCalibreRelocationGeneration';
            if (window[marker] === (\(generation))) return true;
            rendition.on('relocated', (location) => {
                const handler = window.webkit && window.webkit.messageHandlers[\(handler)];
                if (!handler || !location || !location.start || !location.end) return;
                handler.postMessage({
                    event: 'relocated',
                    generation: \(generation),
                    startCFI: String(location.start.cfi || ''),
                    endCFI: String(location.end.cfi || '')
                });
            });
            window[marker] = (\(generation));
            return true;
        })()
        """
    }

    private func evaluate(
        _ script: String,
        in webView: WKWebView,
        completion: @escaping @MainActor (Any?, Error?) -> Void
    ) {
        webView.evaluateJavaScript(script, in: nil, in: Self.contentWorld) { result in
            Task { @MainActor in
                switch result {
                case let .success(value):
                    completion(value, nil)
                case let .failure(error):
                    completion(nil, error)
                }
            }
        }
    }

    private func isCurrent(
        expectedDocument: CalibreReaderDocumentIdentity,
        webView: WKWebView
    ) -> Bool {
        currentDocumentIdentity == expectedDocument
            && self.webView === webView
            && !isInvalidated
    }

    private static func documentIdentity(
        slotID: UUID,
        generation: UInt64,
        url: URL?
    ) -> CalibreReaderDocumentIdentity? {
        guard let url,
              let readerKind = CalibreReaderRouteMatcher.readerKind(for: url),
              let origin = CalibreReaderRouteMatcher.committedOrigin(for: url) else {
            return nil
        }
        return CalibreReaderDocumentIdentity(
            slotID: slotID,
            documentGeneration: generation,
            committedURL: url,
            origin: origin,
            readerKind: readerKind
        )
    }

    static func pageMessagePassesSecurityContract(
        messageWebView: WKWebView?,
        attachedWebView: WKWebView,
        isMainFrame: Bool,
        originScheme: String,
        originHost: String,
        originPort: Int,
        documentOrigin: URL
    ) -> Bool {
        guard let messageWebView,
              messageWebView === attachedWebView,
              isMainFrame else {
            return false
        }
        return originMatches(
            scheme: originScheme,
            host: originHost,
            port: originPort,
            documentOrigin: documentOrigin
        )
    }

    private static func originMatches(
        scheme: String,
        host: String,
        port: Int,
        documentOrigin: URL
    ) -> Bool {
        guard let documentScheme = documentOrigin.scheme,
              let documentHost = documentOrigin.host,
              scheme.caseInsensitiveCompare(documentScheme) == .orderedSame,
              host.caseInsensitiveCompare(documentHost) == .orderedSame else {
            return false
        }

        let defaultPort: Int?
        switch documentScheme.lowercased() {
        case "http": defaultPort = 80
        case "https": defaultPort = 443
        default: defaultPort = nil
        }
        return port == (documentOrigin.port ?? defaultPort)
    }
}
