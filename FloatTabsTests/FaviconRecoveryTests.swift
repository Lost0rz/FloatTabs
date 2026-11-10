import AppKit
import Foundation
import XCTest
@testable import FloatTabs

@MainActor
final class FaviconRecoveryTests: XCTestCase {
    func testRootHTMLDiscoveryRecoversChatGPTAndKeepsWWWAsSeparateOrigin() async throws {
        let imageData = try fixtureImageData(color: .systemBlue)
        let loader = FaviconTestLoader { request, _ in
            let path = request.url?.path
            if path == "/favicon.ico" {
                return (Data(), Self.response(for: request, status: 404))
            }
            if path == "/" {
                let html = #"<link rel="icon" href="/unauth-mweb/favicon.svg">"#
                return (Data(html.utf8), Self.response(for: request, status: 200, mimeType: "text/html"))
            }
            if path == "/unauth-mweb/favicon.svg" {
                return (imageData, Self.response(for: request, status: 200, mimeType: "image/svg+xml"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })

        let chatGPT = try XCTUnwrap(URL(string: "https://chatgpt.com/c/123?secret=private#message"))
        let chatGPTImage = await load(provider, from: chatGPT)
        XCTAssertNotNil(chatGPTImage)
        XCTAssertEqual(loader.requests.prefix(3).compactMap { $0.url?.path }, [
            "/favicon.ico", "/", "/unauth-mweb/favicon.svg",
        ])
        XCTAssertTrue(loader.requests.allSatisfy { $0.url?.query == nil && $0.url?.fragment == nil })

        let countAfterChatGPT = loader.requests.count
        let wwwChatGPT = try XCTUnwrap(URL(string: "https://www.chatgpt.com/c/456?secret=also-private"))
        let wwwImage = await load(provider, from: wwwChatGPT)
        XCTAssertNotNil(wwwImage)
        XCTAssertEqual(loader.requests.count, countAfterChatGPT + 3)
        XCTAssertEqual(Set(loader.requests.compactMap { $0.url?.host }), [
            "chatgpt.com", "www.chatgpt.com",
        ])
        let cachedChatGPTImage = await load(provider, from: chatGPT)
        XCTAssertNotNil(cachedChatGPTImage)
        XCTAssertEqual(loader.requests.count, countAfterChatGPT + 3)
    }

    func testRootFailureFallsBackToSanitizedPathHTMLBeforeLegacyIcons() async throws {
        let bareOrigin = try XCTUnwrap(URL(string: "https://example.test"))
        XCTAssertEqual(
            WebsiteFaviconProvider.pageDiscoveryURLs(for: bareOrigin).map(\.path),
            ["/"]
        )

        let imageData = try fixtureImageData(color: .systemGreen)
        let loader = FaviconTestLoader { request, _ in
            switch request.url?.path {
            case "/favicon.ico", "/":
                return (Data(), Self.response(for: request, status: 404))
            case "/unauth-mweb":
                let html = #"<link rel="apple-touch-icon" href="icons/site.png">"#
                return (Data(html.utf8), Self.response(for: request, status: 200, mimeType: "text/html"))
            case "/icons/site.png":
                return (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
            default:
                return (Data(), Self.response(for: request, status: 404))
            }
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let page = try XCTUnwrap(URL(string: "https://chatgpt.com/unauth-mweb?token=private#fragment"))

        let image = await load(provider, from: page)
        XCTAssertNotNil(image)
        XCTAssertEqual(loader.requests.map { $0.url?.path }, [
            "/favicon.ico", "/", "/unauth-mweb", "/icons/site.png",
        ])
        XCTAssertTrue(loader.requests.allSatisfy { $0.url?.query == nil && $0.url?.fragment == nil })
    }

    func testConcurrentLoadsCoalesceAndSuccessfulImageRemainsCached() async throws {
        let imageData = try fixtureImageData(color: .systemOrange)
        let loader = FaviconTestLoader { request, _ in
            (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let url = try XCTUnwrap(URL(string: "https://www.google.com/search?q=FloatTabs"))
        let completions = expectation(description: "each coalesced subscriber completes once")
        completions.expectedFulfillmentCount = 2
        var completionCount = 0

        provider.load(for: url) { image in
            XCTAssertNotNil(image)
            completionCount += 1
            completions.fulfill()
        }
        provider.load(for: url) { image in
            XCTAssertNotNil(image)
            completionCount += 1
            completions.fulfill()
        }
        await fulfillment(of: [completions], timeout: 2)

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(completionCount, 2)
        let cachedImage = await load(provider, from: url)
        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(loader.requests.count, 1)

        let xURL = try XCTUnwrap(URL(string: "https://x.com/home"))
        let xImage = await load(provider, from: xURL)
        XCTAssertNotNil(xImage)
        XCTAssertEqual(loader.requests.count, 2)
        XCTAssertEqual(Set(loader.requests.compactMap { $0.url?.host }), ["www.google.com", "x.com"])
    }

    func testFailedOriginRetriesOnceWithFreshCachePolicyAndThenCachesRecovery() async throws {
        let imageData = try fixtureImageData(color: .systemPurple)
        let clock = FaviconTestClock(now: 10)
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, _ in
            if request.cachePolicy == .reloadIgnoringLocalCacheData,
               request.url?.path == "/favicon.ico" {
                return (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            monotonicClock: { clock.now },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let url = try XCTUnwrap(URL(string: "https://chatgpt.com/c/987?secret=private"))
        let result = Task { await load(provider, from: url) }

        await retryGate.waitUntilScheduled()
        XCTAssertEqual(retryGate.delays, [15])
        XCTAssertEqual(loader.requests.count, 7)
        XCTAssertTrue(loader.requests.allSatisfy { $0.cachePolicy == .returnCacheDataElseLoad })

        retryGate.resumeNext()
        let recoveredImage = await result.value
        XCTAssertNotNil(recoveredImage)
        XCTAssertEqual(loader.requests.count, 8)
        XCTAssertEqual(loader.requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        let cachedImage = await load(provider, from: url)
        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(loader.requests.count, 8)
        XCTAssertEqual(retryGate.delays, [15])
    }

    func testSecondFailureUses120SecondCooldownAndNormalCallRetriesAfterExpiry() async throws {
        let imageData = try fixtureImageData(color: .systemTeal)
        let clock = FaviconTestClock(now: 20)
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, count in
            if count > 14 {
                return (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            monotonicClock: { clock.now },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let url = try XCTUnwrap(URL(string: "https://chatgpt.com/c/654?token=private"))
        let firstResult = Task { await load(provider, from: url) }

        await retryGate.waitUntilScheduled()
        retryGate.resumeNext()
        let failedImage = await firstResult.value
        XCTAssertNil(failedImage)
        XCTAssertEqual(loader.requests.count, 14)
        XCTAssertEqual(retryGate.delays, [15])

        let cooldownImage = await load(provider, from: url)
        XCTAssertNil(cooldownImage)
        XCTAssertEqual(loader.requests.count, 14)
        clock.now = 139.999
        let earlyRetryImage = await load(provider, from: url)
        XCTAssertNil(earlyRetryImage)
        XCTAssertEqual(loader.requests.count, 14)

        clock.now = 140
        let expiredCooldownImage = await load(provider, from: url)
        XCTAssertNotNil(expiredCooldownImage)
        XCTAssertEqual(loader.requests.count, 15)
    }

    func testTabAndMenuBarRetrySameOriginAndRejectAtoBtoAStaleCallbacks() throws {
        var tabCompletions: [(NSImage?) -> Void] = []
        let tab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, completion in
            tabCompletions.append(completion)
        })
        var profile = makeProfile(url: "https://chatgpt.com/c/one")
        tab.update(profile: profile, isActive: true, isResident: true)
        XCTAssertEqual(tabCompletions.count, 1)
        tabCompletions[0](nil)

        profile.homeURL = URL(string: "https://chatgpt.com/c/two")!
        tab.update(profile: profile, isActive: true, isResident: true)
        XCTAssertEqual(tabCompletions.count, 2)
        let tabImage = fixtureImage(color: .systemBlue)
        tabCompletions[1](tabImage)
        let successfulTabImage = tab.displayedIcon?.tiffRepresentation
        tab.update(profile: profile, isActive: true, isResident: true)
        XCTAssertEqual(tabCompletions.count, 2)
        XCTAssertEqual(tab.displayedIcon?.tiffRepresentation, successfulTabImage)

        var staleTabCompletions: [(NSImage?) -> Void] = []
        let staleTab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, completion in
            staleTabCompletions.append(completion)
        })
        var staleTabProfile = makeProfile(url: "https://chatgpt.com/c/one")
        staleTab.update(profile: staleTabProfile, isActive: true, isResident: true)
        staleTabProfile.homeURL = URL(string: "https://docs.example.test/page")!
        staleTab.update(profile: staleTabProfile, isActive: true, isResident: true)
        staleTabProfile.homeURL = URL(string: "https://chatgpt.com/c/two")!
        staleTab.update(profile: staleTabProfile, isActive: true, isResident: true)
        XCTAssertEqual(staleTabCompletions.count, 3)
        let staleTabFallback = staleTab.displayedIcon?.tiffRepresentation
        staleTabCompletions[0](fixtureImage(color: .systemRed))
        staleTabCompletions[1](fixtureImage(color: .systemOrange))
        XCTAssertEqual(staleTab.displayedIcon?.tiffRepresentation, staleTabFallback)
        staleTabCompletions[2](fixtureImage(color: .systemPurple))
        XCTAssertNotEqual(staleTab.displayedIcon?.tiffRepresentation, staleTabFallback)

        var menuCompletions: [(NSImage?) -> Void] = []
        let defaultsName = "FloatTabsTests.FaviconRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: AppPreferencesStore(defaults: defaults),
            faviconLoader: { _, completion in menuCompletions.append(completion) }
        )
        statusItem.setAttentionPresentation(unreadCount: 2, floatTabsVisible: false)
        let siteA = URL(string: "https://chatgpt.com/c/one")!
        let siteB = URL(string: "https://www.chatgpt.com/c/two")!
        statusItem.setActiveWebApp(name: "ChatGPT", faviconURL: siteA)
        menuCompletions[0](nil)
        statusItem.setActiveWebApp(name: "ChatGPT", faviconURL: URL(string: "https://chatgpt.com/c/three")!)
        XCTAssertEqual(menuCompletions.count, 2)
        let menuImage = fixtureImage(color: .systemGreen)
        menuCompletions[1](menuImage)
        let successfulMenuImage = statusItem.debugStatusButtonImageTIFF
        statusItem.setActiveWebApp(name: "ChatGPT", faviconURL: siteA)
        XCTAssertEqual(menuCompletions.count, 2)
        XCTAssertEqual(statusItem.debugStatusButtonImageTIFF, successfulMenuImage)

        var staleCompletions: [(NSImage?) -> Void] = []
        let staleStatusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: AppPreferencesStore(defaults: defaults),
            faviconLoader: { _, completion in staleCompletions.append(completion) }
        )
        staleStatusItem.setAttentionPresentation(unreadCount: 3, floatTabsVisible: false)
        staleStatusItem.setActiveWebApp(name: "A", faviconURL: siteA)
        staleStatusItem.setActiveWebApp(name: "B", faviconURL: siteB)
        staleStatusItem.setActiveWebApp(name: "A", faviconURL: siteA)
        XCTAssertEqual(staleCompletions.count, 3)
        let fallback = staleStatusItem.debugStatusButtonImageTIFF
        staleCompletions[0](fixtureImage(color: .systemRed))
        staleCompletions[1](fixtureImage(color: .systemOrange))
        XCTAssertEqual(staleStatusItem.debugStatusButtonImageTIFF, fallback)
        XCTAssertEqual(staleStatusItem.attentionPresentation.badge, .count("3"))
        staleCompletions[2](fixtureImage(color: .systemPurple))
        XCTAssertNotEqual(staleStatusItem.debugStatusButtonImageTIFF, fallback)
        XCTAssertEqual(staleStatusItem.attentionPresentation.badge, .count("3"))
    }

    private func load(_ provider: WebsiteFaviconProvider, from url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            provider.load(for: url) { continuation.resume(returning: $0) }
        }
    }

    private func makeProfile(url: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: "ChatGPT",
            homeURL: URL(string: url)!
        )
    }

    private func fixtureImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    private func fixtureImageData(color: NSColor) throws -> Data {
        try XCTUnwrap(fixtureImage(color: color).tiffRepresentation)
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        mimeType: String? = nil
    ) -> URLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: mimeType.map { ["Content-Type": $0] }
        )!
    }
}

@MainActor
private final class FaviconTestLoader {
    typealias Response = (Data, URLResponse)
    typealias Responder = @MainActor (URLRequest, Int) async throws -> Response

    private let responder: Responder
    private(set) var requests: [URLRequest] = []

    init(responder: @escaping Responder) {
        self.responder = responder
    }

    func load(_ request: URLRequest) async throws -> Response {
        requests.append(request)
        return try await responder(request, requests.count)
    }
}

@MainActor
private final class FaviconTestClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class FaviconRetryGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var scheduleWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var delays: [TimeInterval] = []

    func wait(for delay: TimeInterval) async {
        delays.append(delay)
        let readyWaiters = scheduleWaiters.filter { $0.0 <= delays.count }
        scheduleWaiters.removeAll { $0.0 <= delays.count }
        readyWaiters.forEach { $0.1.resume() }
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilScheduled(_ count: Int = 1) async {
        guard delays.count < count else { return }
        await withCheckedContinuation { scheduleWaiters.append((count, $0)) }
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
