import AppKit
import Foundation
import XCTest
import WebKit
@testable import FloatTabs

@MainActor
final class FaviconRecoveryTests: XCTestCase {
    func testRootHTMLDiscoveryRecoversChatGPTAndKeepsWWWAsSeparateOrigin() async throws {
        let imageData = fixtureSVGData()
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
        XCTAssertEqual(loader.requests.prefix(2).compactMap { $0.url?.path }, [
            "/", "/unauth-mweb/favicon.svg",
        ])
        XCTAssertTrue(loader.requests.allSatisfy { $0.url?.query == nil && $0.url?.fragment == nil })

        let countAfterChatGPT = loader.requests.count
        let wwwChatGPT = try XCTUnwrap(URL(string: "https://www.chatgpt.com/c/456?secret=also-private"))
        let wwwImage = await load(provider, from: wwwChatGPT)
        XCTAssertNotNil(wwwImage)
        XCTAssertEqual(loader.requests.count, countAfterChatGPT + 2)
        XCTAssertEqual(Set(loader.requests.compactMap { $0.url?.host }), [
            "chatgpt.com", "www.chatgpt.com",
        ])
        let cachedChatGPTImage = await load(provider, from: chatGPT)
        XCTAssertNotNil(cachedChatGPTImage)
        XCTAssertEqual(loader.requests.count, countAfterChatGPT + 2)
    }

    func testDeclaredCandidatesPreferStandardSizedIconsAndPlaceMaskIconsLast() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://chatgpt.example.test/"))
        let html = """
        <link rel="mask-icon" href="/mask.svg" sizes="any" type="image/svg+xml">
        <link rel="apple-touch-icon" href="/touch.png" sizes="180x180" type="image/png">
        <link rel="icon" href="/unknown.bin">
        <link rel="icon" href="/small.png" sizes="16x16" type="image/png">
        <link rel="icon" href="/retina.ico" sizes="32x32" type="image/x-icon">
        <link rel="icon" href="/dark.svg" sizes="any" type="image/svg+xml" media="(prefers-color-scheme: dark)">
        """

        let candidates = WebsiteFaviconProvider.discoveredFaviconCandidates(
            in: html,
            baseURL: baseURL
        )

        XCTAssertEqual(candidates.map(\.url.path), [
            "/retina.ico", "/small.png", "/unknown.bin", "/dark.svg", "/touch.png", "/mask.svg",
        ])
        XCTAssertEqual(candidates.first?.kind, .icon)
        XCTAssertEqual(candidates.last?.kind, .mask)
    }

    func testDeclaredHTTPSCDNCandidateLoadsForCommittedPageOrigin() async throws {
        let imageData = try fixtureImageData(color: .systemPurple)
        let pageURL = try XCTUnwrap(URL(string: "https://committed.example.test/page"))
        let cdnIconURL = try XCTUnwrap(URL(string: "https://cdn.example.test/brand/icon.png"))
        let sameOriginIconURL = try XCTUnwrap(URL(string: "https://committed.example.test/icon.png"))
        let loader = FaviconTestLoader { request, _ in
            (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        provider.setDOMCandidates(
            [
                .declared(cdnIconURL, sourceOrder: 0),
                .declared(sameOriginIconURL, sourceOrder: 1),
            ],
            for: pageURL
        )

        let image = await load(provider, from: pageURL)

        XCTAssertNotNil(image)
        XCTAssertEqual(loader.requests.compactMap(\.url), [cdnIconURL])
        XCTAssertTrue(loader.requests.allSatisfy {
            !$0.httpShouldHandleCookies && $0.timeoutInterval == 8
        })
    }

    func testTransparentDeclaredIconIsSkippedForNextVisibleCandidate() async throws {
        let transparentData = try fixtureTransparentImageData()
        let visibleData = try fixtureImageData(color: .systemBlue)
        let loader = FaviconTestLoader { request, _ in
            let data = request.url?.path == "/transparent.png" ? transparentData : visibleData
            return (data, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let pageURL = try XCTUnwrap(URL(string: "https://icons.example.test/"))
        let transparentURL = try XCTUnwrap(URL(string: "https://icons.example.test/transparent.png"))
        let visibleURL = try XCTUnwrap(URL(string: "https://icons.example.test/brand.png"))
        provider.setDOMCandidates(
            [.declared(transparentURL), .declared(visibleURL, sourceOrder: 1)],
            for: pageURL
        )

        let image = await load(provider, from: pageURL)

        XCTAssertNotNil(image)
        XCTAssertEqual(loader.requests.compactMap(\.url), [transparentURL, visibleURL])
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
            "/", "/unauth-mweb", "/icons/site.png",
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

        XCTAssertEqual(loader.requests.count, 3)
        XCTAssertEqual(completionCount, 2)
        let cachedImage = await load(provider, from: url)
        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(loader.requests.count, 3)

        let xURL = try XCTUnwrap(URL(string: "https://x.com/home"))
        let xImage = await load(provider, from: xURL)
        XCTAssertNotNil(xImage)
        XCTAssertEqual(loader.requests.count, 6)
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
        XCTAssertEqual(loader.requests.count, 10)
        XCTAssertEqual(loader.requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        let cachedImage = await load(provider, from: url)
        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(loader.requests.count, 10)
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
        XCTAssertEqual(loader.requests.count, 17)
    }

    func testActiveDemandUsesBoundedProgressiveCooldownThrough900Seconds() async throws {
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, _ in
            (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let url = try XCTUnwrap(URL(string: "https://chatgpt.example.test/c/123"))
        let consumerID = UUID()
        provider.subscribe(for: url, consumerID: consumerID, automaticallyRetries: true) { _ in }

        let expectedDelays: [TimeInterval] = [15, 120, 15, 240, 15, 480, 15, 900, 15, 900]
        for index in expectedDelays.indices {
            await retryGate.waitUntilScheduled(index + 1)
            XCTAssertEqual(retryGate.delays[index], expectedDelays[index])
            retryGate.resumeNext()
        }

        provider.cancel(consumerID: consumerID)
        retryGate.resumeNext()
        XCTAssertEqual(retryGate.delays, expectedDelays)
        XCTAssertEqual(loader.requests.count, 70)
    }

    func testInactiveConsumerDoesNotScheduleAnotherCooldownPoll() async throws {
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, _ in
            (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let url = try XCTUnwrap(URL(string: "https://chatgpt.example.test/c/123"))
        let consumerID = UUID()
        let failed = expectation(description: "inactive consumer receives the bounded fresh retry result")
        provider.subscribe(for: url, consumerID: consumerID, automaticallyRetries: false) { image in
            XCTAssertNil(image)
            failed.fulfill()
        }

        await retryGate.waitUntilScheduled()
        XCTAssertEqual(retryGate.delays, [15])
        retryGate.resumeNext()
        await fulfillment(of: [failed], timeout: 2)

        XCTAssertEqual(loader.requests.count, 14)
        XCTAssertEqual(retryGate.delays, [15])
        provider.cancel(consumerID: consumerID)
    }

    func testUnsafeCrossOriginAndNonHTTPDOMCandidatesAreRejectedCookieLess() async throws {
        let loader = FaviconTestLoader { request, _ in
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { _ in }
        )
        let pageURL = try XCTUnwrap(URL(string: "https://chatgpt.example.test/c/123"))
        let insecureCDNIconURL = try XCTUnwrap(URL(string: "http://cdn.example.test/brand/icon.png?v=4"))
        provider.setDOMCandidates(
            [
                insecureCDNIconURL,
                insecureCDNIconURL,
                URL(string: "javascript:alert(1)")!,
                URL(string: "data:image/png;base64,AA==")!,
                URL(string: "file:///tmp/icon.png")!,
            ],
            for: pageURL
        )

        let image = await load(provider, from: pageURL)

        XCTAssertNil(image)
        XCTAssertFalse(loader.requests.isEmpty)
        XCTAssertFalse(loader.requests.contains { $0.url == insecureCDNIconURL })
        XCTAssertLessThanOrEqual(loader.requests.count, 14)
        XCTAssertTrue(loader.requests.allSatisfy {
            $0.url?.host == "chatgpt.example.test"
                && !$0.httpShouldHandleCookies
                && $0.timeoutInterval == 8
        })
    }

    func testLateDOMCandidateReplacesFallbackAndMenuConsumerSurvivesTabDetach() async throws {
        let fallbackData = try fixtureImageData(color: .systemRed)
        let declaredData = try fixtureImageData(color: .systemBlue)
        let loader = FaviconTestLoader { request, _ in
            switch request.url?.path {
            case "/favicon.ico":
                return (fallbackData, Self.response(for: request, status: 200, mimeType: "image/png"))
            case "/assets/brand.png":
                return (declaredData, Self.response(for: request, status: 200, mimeType: "image/png"))
            default:
                return (Data(), Self.response(for: request, status: 404))
            }
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let pageURL = try XCTUnwrap(URL(string: "https://chatgpt.example.test/c/123"))
        let iconURL = try XCTUnwrap(URL(string: "https://chatgpt.example.test/assets/brand.png"))
        let tabConsumerID = UUID()
        let menuConsumerID = UUID()
        let initialConsumers = expectation(description: "tab and menu both receive the current fallback")
        initialConsumers.expectedFulfillmentCount = 2
        let improvedMenuImage = expectation(description: "menu receives the better declared icon")
        var tabImages: [NSImage?] = []
        var menuImages: [NSImage?] = []

        provider.subscribe(for: pageURL, consumerID: tabConsumerID) { image in
            tabImages.append(image)
            initialConsumers.fulfill()
        }

        let defaultsName = "FloatTabsTests.FaviconRecovery.LateDOM.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: AppPreferencesStore(defaults: defaults),
            faviconLoader: { url, completion in
                provider.subscribe(for: url, consumerID: menuConsumerID) { image in
                    menuImages.append(image)
                    if menuImages.count == 1 {
                        initialConsumers.fulfill()
                    } else if menuImages.count == 2 {
                        improvedMenuImage.fulfill()
                    }
                    completion(image)
                }
            },
            faviconCanceller: { provider.cancel(consumerID: $0) }
        )
        statusItem.setActiveWebApp(name: "ChatGPT", faviconURL: pageURL)
        await fulfillment(of: [initialConsumers], timeout: 2)
        let fallbackStatusImage = statusItem.debugStatusButtonImageTIFF

        // A hidden panel may detach its Tab view. The independently selected
        // menu-bar consumer remains subscribed and receives the improved icon.
        provider.cancel(consumerID: tabConsumerID)
        provider.setDOMCandidates([.declared(iconURL)], for: pageURL)
        await fulfillment(of: [improvedMenuImage], timeout: 2)

        XCTAssertEqual(tabImages.count, 1)
        XCTAssertEqual(menuImages.count, 2)
        XCTAssertNotEqual(statusItem.debugStatusButtonImageTIFF, fallbackStatusImage)
        XCTAssertTrue(loader.requests.allSatisfy { !$0.httpShouldHandleCookies })
        XCTAssertEqual(loader.requests.last?.url, iconURL)
        provider.cancel(consumerID: menuConsumerID)
    }

    func testSamePriorityDOMResourceChangeUpdatesOnlyStillActiveConsumers() async throws {
        let oldData = try fixtureImageData(color: .systemRed)
        let newData = try fixtureImageData(color: .systemBlue)
        let gate = FaviconFetchGate()
        let pageURL = try XCTUnwrap(URL(string: "https://same-priority.example.test/page"))
        let oldURL = try XCTUnwrap(URL(string: "https://same-priority.example.test/old.png"))
        let newURL = try XCTUnwrap(URL(string: "https://same-priority.example.test/new.png"))
        let loader = FaviconTestLoader { request, _ in
            if request.url == newURL {
                await gate.suspend()
                return (newData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            return (
                oldData,
                Self.response(for: request, status: 200, mimeType: "image/png")
            )
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let tabID = UUID()
        let menuID = UUID()
        let initial = expectation(description: "both current consumers receive the cached icon")
        initial.expectedFulfillmentCount = 2
        let updated = expectation(description: "remaining consumer receives the new same-rank resource")
        var tabImages: [NSImage?] = []
        var menuImages: [NSImage?] = []

        provider.setDOMCandidates([.declared(oldURL)], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: tabID) { image in
            tabImages.append(image)
            initial.fulfill()
        }
        provider.subscribe(for: pageURL, consumerID: menuID) { image in
            menuImages.append(image)
            if menuImages.count == 1 {
                initial.fulfill()
            } else {
                updated.fulfill()
            }
        }
        await fulfillment(of: [initial], timeout: 2)

        XCTAssertEqual(
            WebsiteFaviconProvider.Candidate.declared(oldURL).priority,
            WebsiteFaviconProvider.Candidate.declared(newURL).priority
        )
        provider.setDOMCandidates([.declared(newURL)], for: pageURL)
        await gate.waitUntilSuspended()
        provider.cancel(consumerID: tabID)
        gate.resumeNext()
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(loader.requests.compactMap(\.url), [oldURL, newURL])
        XCTAssertEqual(tabImages.count, 1)
        XCTAssertEqual(menuImages.count, 2)
        XCTAssertNotEqual(
            tabImages[0]?.tiffRepresentation,
            menuImages[1]?.tiffRepresentation
        )
        provider.cancel(consumerID: menuID)
    }

    func testManualReloadFetchesFreshBytesForSameResourceAndDeduplicatesOrigin() async throws {
        let oldData = try fixtureImageData(color: .systemRed)
        let newData = try fixtureImageData(color: .systemBlue)
        let pageURL = try XCTUnwrap(URL(string: "https://reload-refresh.example.test/page"))
        let iconURL = try XCTUnwrap(URL(string: "https://reload-refresh.example.test/icon.png"))
        let sameOriginURL = try XCTUnwrap(URL(string: "https://reload-refresh.example.test/other"))
        let loader = FaviconTestLoader { request, count in
            let data = count == 1 ? oldData : newData
            return (data, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let tabConsumer = UUID()
        let menuConsumer = UUID()
        let staleConsumer = UUID()
        let initial = expectation(description: "all consumers receive the original icon")
        initial.expectedFulfillmentCount = 3
        let refreshed = expectation(description: "current Tab and menu consumers receive fresh bytes")
        refreshed.expectedFulfillmentCount = 2
        var tabImages: [NSImage?] = []
        var menuImages: [NSImage?] = []
        var staleImages: [NSImage?] = []
        provider.setDOMCandidates([.declared(iconURL)], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: tabConsumer) { image in
            tabImages.append(image)
            if tabImages.count == 1 {
                initial.fulfill()
            } else {
                refreshed.fulfill()
            }
        }
        provider.subscribe(for: pageURL, consumerID: menuConsumer) { image in
            menuImages.append(image)
            if menuImages.count == 1 {
                initial.fulfill()
            } else {
                refreshed.fulfill()
            }
        }
        provider.subscribe(for: pageURL, consumerID: staleConsumer) { image in
            staleImages.append(image)
            initial.fulfill()
        }
        await fulfillment(of: [initial], timeout: 2)

        provider.cancel(consumerID: staleConsumer)
        provider.refreshAfterManualReload(
            candidateReadResult: .candidates([.declared(iconURL)]),
            committedURL: pageURL,
            for: [pageURL, sameOriginURL]
        )
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(loader.requests.count, 2)
        XCTAssertEqual(loader.requests[0].cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(loader.requests[1].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(loader.requests.map(\.url), [iconURL, iconURL])
        XCTAssertEqual(tabImages.count, 2)
        XCTAssertEqual(menuImages.count, 2)
        XCTAssertEqual(staleImages.count, 1, "cancelled consumer must not receive a stale completion")
        XCTAssertNotEqual(
            tabImages[0]?.tiffRepresentation,
            tabImages[1]?.tiffRepresentation,
            "same URL must be decoded again after an explicit Reload"
        )
        XCTAssertEqual(tabImages[1]?.tiffRepresentation, menuImages[1]?.tiffRepresentation)
        provider.cancel(consumerID: tabConsumer)
        provider.cancel(consumerID: menuConsumer)
    }

    func testManualReloadRefreshesTabAndCommittedOriginsSeparately() async throws {
        let homeOldData = try fixtureImageData(color: .systemOrange)
        let homeNewData = try fixtureImageData(color: .systemTeal)
        let committedOldData = try fixtureImageData(color: .systemBlue)
        let committedNewData = try fixtureImageData(color: .systemRed)
        let tabHomeURL = try XCTUnwrap(URL(string: "https://bare-origin.example.test/home"))
        let committedURL = try XCTUnwrap(URL(string: "https://www.example.test/page"))
        let homeIconURL = try XCTUnwrap(URL(string: "https://bare-origin.example.test/home-icon.png"))
        let committedIconURL = try XCTUnwrap(URL(string: "https://cdn.example.test/shared-icon.png"))
        let loader = FaviconTestLoader { request, _ in
            let isFresh = request.cachePolicy == .reloadIgnoringLocalCacheData
            let data: Data
            switch request.url?.host {
            case "bare-origin.example.test": data = isFresh ? homeNewData : homeOldData
            case "cdn.example.test": data = isFresh ? committedNewData : committedOldData
            default: data = committedNewData
            }
            return (data, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let tabConsumer = UUID()
        let menuConsumer = UUID()
        let initial = expectation(description: "each origin receives its cached icon")
        initial.expectedFulfillmentCount = 2
        let refreshed = expectation(description: "both distinct origin consumers receive fresh icons")
        refreshed.expectedFulfillmentCount = 2
        var tabImages: [NSImage?] = []
        var menuImages: [NSImage?] = []
        provider.setDOMCandidates([.declared(homeIconURL)], for: tabHomeURL)
        provider.setDOMCandidates([.declared(committedIconURL)], for: committedURL)
        provider.subscribe(for: tabHomeURL, consumerID: tabConsumer) { image in
            tabImages.append(image)
            (tabImages.count == 1 ? initial : refreshed).fulfill()
        }
        provider.subscribe(for: committedURL, consumerID: menuConsumer) { image in
            menuImages.append(image)
            (menuImages.count == 1 ? initial : refreshed).fulfill()
        }
        await fulfillment(of: [initial], timeout: 2)

        provider.refreshAfterManualReload(
            candidateReadResult: .candidates([.declared(committedIconURL)]),
            committedURL: committedURL,
            for: [committedURL, tabHomeURL]
        )
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(loader.requests.count, 4)
        XCTAssertEqual(loader.requests.filter { $0.cachePolicy == .returnCacheDataElseLoad }.count, 2)
        let freshRequests = loader.requests.filter {
            $0.cachePolicy == .reloadIgnoringLocalCacheData
        }
        XCTAssertEqual(freshRequests.count, 2)
        XCTAssertEqual(Set(freshRequests.compactMap(\.url)), Set([homeIconURL, committedIconURL]))
        XCTAssertFalse(loader.requests.contains { $0.url?.host == "www.example.test" })
        XCTAssertTrue(loader.requests.allSatisfy {
            !$0.httpShouldHandleCookies && $0.timeoutInterval == 8
        })
        XCTAssertEqual(tabImages.count, 2)
        XCTAssertEqual(menuImages.count, 2)
        XCTAssertNotEqual(tabImages[0]?.tiffRepresentation, tabImages[1]?.tiffRepresentation)
        XCTAssertNotEqual(menuImages[0]?.tiffRepresentation, menuImages[1]?.tiffRepresentation)
        XCTAssertNotEqual(tabImages[1]?.tiffRepresentation, menuImages[1]?.tiffRepresentation)
        provider.cancel(consumerID: tabConsumer)
        provider.cancel(consumerID: menuConsumer)
    }

    func testManualReloadWithNoCommittedDOMCandidatesRetainsHomeOriginCandidates() async throws {
        let oldData = try fixtureImageData(color: .systemOrange)
        let newData = try fixtureImageData(color: .systemTeal)
        let homeURL = try XCTUnwrap(URL(string: "https://home-a.example.test/"))
        let committedURL = try XCTUnwrap(URL(string: "https://committed-b.example.test/page"))
        let homeIconURL = try XCTUnwrap(URL(string: "https://home-a.example.test/icon.png"))
        let loader = FaviconTestLoader { request, _ in
            guard request.url == homeIconURL else {
                return (Data(), Self.response(for: request, status: 404))
            }
            let data = request.cachePolicy == .reloadIgnoringLocalCacheData ? newData : oldData
            return (data, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let tabConsumer = UUID()
        let initial = expectation(description: "home origin has a validated cached candidate")
        let refreshed = expectation(description: "home origin refresh uses its own candidate")
        var images: [NSImage?] = []
        provider.setDOMCandidates([.declared(homeIconURL)], for: homeURL)
        provider.subscribe(for: homeURL, consumerID: tabConsumer) { image in
            images.append(image)
            (images.count == 1 ? initial : refreshed).fulfill()
        }
        await fulfillment(of: [initial], timeout: 2)

        provider.refreshAfterManualReload(
            candidateReadResult: .noCandidates,
            committedURL: committedURL,
            for: [committedURL, homeURL]
        )
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(images.count, 2)
        XCTAssertNotEqual(images[0]?.tiffRepresentation, images[1]?.tiffRepresentation)
        XCTAssertTrue(loader.requests.contains {
            $0.url == homeIconURL && $0.cachePolicy == .reloadIgnoringLocalCacheData
        })
        provider.cancel(consumerID: tabConsumer)
    }

    func testFailedManualReloadRefreshRetainsExistingImage() async throws {
        let oldData = try fixtureImageData(color: .systemGreen)
        let retryGate = FaviconRetryGate()
        let pageURL = try XCTUnwrap(URL(string: "https://reload-retain.example.test/"))
        let iconURL = try XCTUnwrap(URL(string: "https://reload-retain.example.test/icon.png"))
        let loader = FaviconTestLoader { request, _ in
            guard request.cachePolicy == .returnCacheDataElseLoad else {
                throw URLError(.timedOut)
            }
            return (oldData, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let consumerID = UUID()
        var delivered: [NSImage?] = []
        let loaded = expectation(description: "valid previous image is cached")
        provider.setDOMCandidates([.declared(iconURL)], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: consumerID) { image in
            delivered.append(image)
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 2)
        let originalImage = try XCTUnwrap(delivered.first ?? nil)

        provider.refreshAfterManualReload(
            candidateReadResult: .candidates([.declared(iconURL)]),
            committedURL: pageURL,
            for: [pageURL]
        )
        await retryGate.waitUntilScheduled()

        let retainedDuringRetry = await load(provider, from: pageURL)
        XCTAssertTrue(retainedDuringRetry === originalImage)
        XCTAssertEqual(delivered.count, 1, "failed fresh fetch must not clear or replace the old image")
        XCTAssertTrue(loader.requests.dropFirst().allSatisfy {
            $0.cachePolicy == .reloadIgnoringLocalCacheData
        })
        XCTAssertGreaterThan(loader.requests.count, 1)

        provider.cancel(consumerID: consumerID)
        retryGate.resumeNext()
        let retainedAfterCancel = await load(provider, from: pageURL)
        XCTAssertTrue(retainedAfterCancel === originalImage)
    }

    func testManualReloadIntentCapturesAndConsumesOnlyItsExactGeneration() {
        let identity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 4,
            webViewInstanceID: UUID()
        )
        let otherIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 5,
            webViewInstanceID: UUID()
        )
        var intent = ManualFaviconReloadIntent(
            runtimeIdentity: identity,
            baselineNavigationGeneration: 17
        )

        XCTAssertEqual(
            intent.recordNavigationStart(runtimeIdentity: identity, navigationGeneration: 17),
            .ignored
        )
        XCTAssertEqual(
            intent.recordNavigationStart(runtimeIdentity: identity, navigationGeneration: 18),
            .captured
        )
        XCTAssertFalse(intent.consumeNavigationFinish(runtimeIdentity: identity, navigationGeneration: 17))
        XCTAssertFalse(intent.consumeNavigationFinish(runtimeIdentity: otherIdentity, navigationGeneration: 18))
        XCTAssertTrue(intent.consumeNavigationFinish(runtimeIdentity: identity, navigationGeneration: 18))
        XCTAssertFalse(intent.consumeNavigationFinish(runtimeIdentity: identity, navigationGeneration: 18))

        var replacedRuntimeIntent = ManualFaviconReloadIntent(
            runtimeIdentity: identity,
            baselineNavigationGeneration: 17
        )
        XCTAssertEqual(
            replacedRuntimeIntent.recordNavigationStart(
                runtimeIdentity: otherIdentity,
                navigationGeneration: 18
            ),
            .invalidated
        )

        var expiredIntent = ManualFaviconReloadIntent(
            runtimeIdentity: identity,
            baselineNavigationGeneration: 17,
            requestedAt: 100
        )
        XCTAssertEqual(
            expiredIntent.recordNavigationStart(
                runtimeIdentity: identity,
                navigationGeneration: 18,
                at: 116
            ),
            .invalidated
        )
    }

    func testRemovingUncachedDOMCandidateFallsBackWithoutStrandingConsumer() async throws {
        let declaredData = try fixtureImageData(color: .systemRed)
        let fallbackData = try fixtureImageData(color: .systemBlue)
        let gate = FaviconFetchGate()
        let pageURL = try XCTUnwrap(URL(string: "https://empty-dom.example.test/page"))
        let declaredURL = try XCTUnwrap(URL(string: "https://empty-dom.example.test/declared.png"))
        let loader = FaviconTestLoader { request, _ in
            if request.url == declaredURL {
                await gate.suspend()
                return (declaredData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            if request.url?.path == "/favicon.ico" {
                return (fallbackData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { _ in }
        )
        let consumerID = UUID()
        let iconLoaded = expectation(description: "the still-active consumer receives the fallback icon")
        var delivered: [NSImage?] = []

        provider.setDOMCandidates([.declared(declaredURL)], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: consumerID) { image in
            delivered.append(image)
            iconLoaded.fulfill()
        }
        await gate.waitUntilSuspended()

        provider.setDOMCandidates([WebsiteFaviconProvider.Candidate](), for: pageURL)
        gate.resumeNext()
        await fulfillment(of: [iconLoaded], timeout: 2)

        let result = try XCTUnwrap(delivered.first ?? nil)
        let expected = try XCTUnwrap(NSImage(data: fallbackData)?.tiffRepresentation)
        XCTAssertEqual(result.tiffRepresentation, expected)
        XCTAssertEqual(loader.requests.filter { $0.url == declaredURL }.count, 1)
        XCTAssertTrue(loader.requests.contains { $0.url?.path == "/favicon.ico" })
        provider.cancel(consumerID: consumerID)
    }

    func testSameResourceWithChangedMetadataDoesNotDownloadTwice() async throws {
        let imageData = try fixtureImageData(color: .systemOrange)
        let pageURL = try XCTUnwrap(URL(string: "https://same-resource.example.test/"))
        let iconURL = try XCTUnwrap(URL(string: "https://same-resource.example.test/icon.png"))
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let loader = FaviconTestLoader { request, _ in
            (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            diagnosticRecorder: diagnostics
        )
        let consumerID = UUID()
        var images: [NSImage?] = []
        let initial = expectation(description: "same resource is fetched")
        let refreshed = expectation(description: "same resource metadata reuses the cache")
        let compact = WebsiteFaviconProvider.Candidate(
            url: iconURL,
            kind: .icon,
            sizes: "16x16",
            type: "image/x-icon",
            mediaSpecific: false,
            sourceOrder: 0
        )
        let preferred = WebsiteFaviconProvider.Candidate(
            url: iconURL,
            kind: .icon,
            sizes: "32x32",
            type: "image/png",
            mediaSpecific: false,
            sourceOrder: 0
        )
        provider.setDOMCandidates([compact], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: consumerID) { image in
            images.append(image)
            (images.count == 1 ? initial : refreshed).fulfill()
        }
        await fulfillment(of: [initial], timeout: 2)
        provider.setDOMCandidates([preferred], for: pageURL)
        await fulfillment(of: [refreshed], timeout: 2)

        XCTAssertEqual(compact.priority, 11)
        XCTAssertEqual(preferred.priority, 0)
        XCTAssertEqual(loader.requests.compactMap(\.url), [iconURL])
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(writer.events.contains { event in
            guard event.event == "favicon.cache_update",
                  case .string("reused_same_resource") = event.fields["outcome"] else {
                return false
            }
            return true
        })
        provider.cancel(consumerID: consumerID)
    }

    func testFailedSamePriorityResourceKeepsCachedIconAndReportsDecodeStage() async throws {
        let oldData = try fixtureImageData(color: .systemPurple)
        let pageURL = try XCTUnwrap(URL(string: "https://retained.example.test/"))
        let oldURL = try XCTUnwrap(URL(string: "https://retained.example.test/old.png"))
        let brokenURL = try XCTUnwrap(URL(string: "https://retained.example.test/broken.png"))
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, _ in
            if request.url == oldURL {
                return (oldData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            if request.url == brokenURL {
                return (Data("not an image".utf8), Self.response(for: request, status: 200))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { await retryGate.wait(for: $0) },
            diagnosticRecorder: diagnostics
        )
        let consumerID = UUID()
        var delivered: [NSImage?] = []
        let loaded = expectation(description: "existing valid icon arrives")
        provider.setDOMCandidates([.declared(oldURL)], for: pageURL)
        provider.subscribe(for: pageURL, consumerID: consumerID) { image in
            delivered.append(image)
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 2)
        let originalImage = try XCTUnwrap(delivered.first ?? nil)

        provider.setDOMCandidates([.declared(brokenURL)], for: pageURL)
        await retryGate.waitUntilScheduled()
        retryGate.resumeNext()
        await waitForDiagnostic(writer) { events in
            events.contains { event in
                event.event == "favicon.cache_update"
                    && event.fields["outcome"] == .string("retained_previous")
            }
        }

        provider.cancel(consumerID: consumerID)
        retryGate.resumeNext()

        let retainedImage = await load(provider, from: pageURL)
        XCTAssertTrue(retainedImage === originalImage)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertTrue(writer.events.contains { event in
            guard event.event == "favicon.fetch_attempt",
                  case let .string(stages) = event.fields["failure_stages"] else { return false }
            return stages.contains("image_decode_failed")
        })
        provider.cancel(consumerID: consumerID)
    }

    func testDOMAndNetworkFailureStagesAreDistinctAndPrivacySafe() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let transparentData = try fixtureTransparentImageData()
        let pageURL = try XCTUnwrap(URL(string: "https://failure-stages.example.test/"))
        let candidates = [
            URL(string: "https://failure-stages.example.test/http.png")!,
            URL(string: "https://failure-stages.example.test/timeout.png")!,
            URL(string: "https://failure-stages.example.test/broken.png?token=private-favicon-token")!,
            URL(string: "https://failure-stages.example.test/transparent.png")!,
        ].enumerated().map { index, url in
            WebsiteFaviconProvider.Candidate(
                url: url,
                kind: .icon,
                sizes: "",
                type: "image/png",
                mediaSpecific: false,
                sourceOrder: index
            )
        }
        let loader = FaviconTestLoader { request, _ in
            switch request.url?.path {
            case "/http.png":
                return (Data(), Self.response(for: request, status: 403))
            case "/timeout.png":
                throw URLError(.timedOut)
            case "/broken.png":
                return (Data("invalid image".utf8), Self.response(for: request, status: 200))
            case "/transparent.png":
                return (transparentData, Self.response(for: request, status: 200))
            default:
                return (Data(), Self.response(for: request, status: 404))
            }
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { _ in },
            diagnosticRecorder: diagnostics
        )
        provider.setDOMCandidates(candidates, for: pageURL)
        let image = await load(provider, from: pageURL)
        XCTAssertNil(image)

        let fetchEvents = writer.events.filter { $0.event == "favicon.fetch_attempt" }
        let failureStages = fetchEvents.compactMap { event -> String? in
            guard case let .string(value) = event.fields["failure_stages"] else { return nil }
            return value
        }.joined(separator: ",")
        XCTAssertTrue(failureStages.contains("http_status"))
        XCTAssertTrue(failureStages.contains("request_timed_out"))
        XCTAssertTrue(failureStages.contains("image_decode_failed"))
        XCTAssertTrue(failureStages.contains("no_visible_pixels"))
        let loggedBytes = writer.lines.reduce(into: Data()) { $0.append($1) }
        let loggedText = String(decoding: loggedBytes, as: UTF8.self)
        XCTAssertFalse(loggedText.contains("private-favicon-token"))
        XCTAssertFalse(loggedText.contains("broken.png"))

        XCTAssertEqual(
            WebsiteFaviconProvider.parseDOMCandidateReadResult(.success("[]")),
            .noCandidates
        )
        XCTAssertEqual(
            WebsiteFaviconProvider.parseDOMCandidateReadResult(
                .failure(URLError(.cannotParseResponse))
            ),
            .readFailed
        )
        XCTAssertEqual(
            WebsiteFaviconProvider.parseDOMCandidateReadResult(
                .success("[{\"href\":\"https://failure-stages.example.test/icon.png\",\"kind\":\"icon\"}]")
            ),
            .candidates([.declared(URL(string: "https://failure-stages.example.test/icon.png")!)])
        )
    }

    func testICOFixtureDecodesAsAnActualICOFile() async throws {
        let icoData = try fixtureICOData(color: .systemPurple)
        let loader = FaviconTestLoader { request, _ in
            if request.url?.path == "/favicon.ico" {
                return (icoData, Self.response(for: request, status: 200, mimeType: "image/vnd.microsoft.icon"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(dataLoader: { try await loader.load($0) })
        let url = try XCTUnwrap(URL(string: "https://icons.example.test/"))

        let image = await load(provider, from: url)

        XCTAssertNotNil(image)
        XCTAssertEqual(loader.requests.count, 2)
        XCTAssertEqual(loader.requests.map { $0.url?.path }, ["/", "/favicon.ico"])
    }

    func testWebKitDOMReaderResolvesOnlyHTTPIconDeclarations() async throws {
        let webView = WKWebView(frame: .zero)
        let window = NSWindow(
            contentRect: NSRect(x: -2_000, y: -2_000, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderOut(nil)
        let html = """
        <base href="https://chatgpt.example.test/unauth-mweb/">
        <link rel="stylesheet" href="/site.css">
        <link rel="mask-icon" href="https://cdn.example.test/brand.svg" sizes="any" type="image/svg+xml">
        <link rel="apple-touch-icon" href="icons/apple.png" sizes="180x180" type="image/png">
        <link rel="shortcut icon" href="/icons/favicon.svg" sizes="any" type="image/svg+xml">
        <link rel="icon" href="/icons/dark-only.png" media="(max-width: 1px)">
        <link rel="icon" href="javascript:alert(1)">
        <link rel="icon" href="data:image/png;base64,AA==">
        """
        let htmlLiteral = String(
            data: try JSONSerialization.data(withJSONObject: html, options: .fragmentsAllowed),
            encoding: .utf8
        )!
        let injected = expectation(description: "synthetic DOM fixture installed")
        webView.evaluateJavaScript(
            "document.head.innerHTML = \(htmlLiteral)",
            in: nil,
            in: .page
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Could not install synthetic DOM fixture: \(error)")
            }
            injected.fulfill()
        }
        await fulfillment(of: [injected], timeout: 5)

        let readResult: WebsiteFaviconProvider.DOMCandidateReadResult = await withCheckedContinuation { continuation in
            WebsiteFaviconProvider.readDOMFaviconCandidates(from: webView) {
                continuation.resume(returning: $0)
            }
        }
        guard case let .candidates(candidates) = readResult else {
            return XCTFail("Expected declared DOM candidates, got \(readResult)")
        }
        XCTAssertEqual(candidates.map { $0.url.absoluteString }, [
            "https://chatgpt.example.test/icons/favicon.svg",
            "https://chatgpt.example.test/unauth-mweb/icons/apple.png",
            "https://cdn.example.test/brand.svg",
        ])
        XCTAssertEqual(candidates.first?.kind, .icon)
        XCTAssertEqual(candidates.last?.kind, .mask)
    }

    func testTabIconAppearanceUsesResidencyAcrossSelectionMatrix() {
        let icon = fixtureImage(color: .systemOrange)
        let profile = makeProfile(url: "https://www.google.com/")
        var imagesByResidency: [Bool: [Data]] = [:]

        for isActive in [false, true] {
            for isResident in [false, true] {
                let tab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
                tab.update(profile: profile, isActive: isActive, isResident: isResident)
                tab.setSourceIcon(icon)

                let displayed = try! XCTUnwrap(tab.displayedIcon)
                let data = try! XCTUnwrap(displayed.tiffRepresentation)
                XCTAssertEqual(tab.displayedIconAlpha, isResident ? 1 : 0.38, accuracy: 0.001)
                XCTAssertEqual(tab.isShowingLabel, isActive)
                if isResident {
                    XCTAssertTrue(displayed === icon)
                } else {
                    XCTAssertFalse(displayed === icon)
                    XCTAssertNotEqual(data, icon.tiffRepresentation)
                }
                imagesByResidency[isResident, default: []].append(data)
            }
        }

        XCTAssertEqual(imagesByResidency[false]?.count, 2)
        XCTAssertEqual(imagesByResidency[true]?.count, 2)
        XCTAssertEqual(imagesByResidency[false]?[0], imagesByResidency[false]?[1])
        XCTAssertEqual(imagesByResidency[true]?[0], imagesByResidency[true]?[1])
    }

    func testMultipleUnselectedResidentsStayBrightAndReleasedHoverStaysSubdued() {
        let profile = makeProfile(url: "https://resident.example.test/")
        let firstIcon = fixtureImage(color: .black)
        let secondIcon = fixtureImage(color: .systemBlue)
        let firstResident = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        let secondResident = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        firstResident.update(profile: profile, isActive: false, isResident: true)
        secondResident.update(profile: profile, isActive: false, isResident: true)
        firstResident.setSourceIcon(firstIcon)
        secondResident.setSourceIcon(secondIcon)
        firstResident.setHovered(true)

        XCTAssertTrue(firstResident.displayedIcon === firstIcon)
        XCTAssertTrue(secondResident.displayedIcon === secondIcon)
        XCTAssertEqual(firstResident.displayedIconAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(secondResident.displayedIconAlpha, 1, accuracy: 0.001)

        let releasedSelected = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        releasedSelected.update(profile: profile, isActive: true, isResident: false)
        releasedSelected.setSourceIcon(firstIcon)
        XCTAssertFalse(releasedSelected.displayedIcon === firstIcon)
        XCTAssertEqual(releasedSelected.displayedIconAlpha, 0.38, accuracy: 0.001)
        releasedSelected.setHovered(true)
        XCTAssertFalse(releasedSelected.displayedIcon === firstIcon)
        XCTAssertEqual(releasedSelected.displayedIconAlpha, 0.60, accuracy: 0.001)
        XCTAssertLessThan(releasedSelected.displayedIconAlpha, 1)

        let templateIcon = fixtureImage(color: .systemPurple)
        templateIcon.isTemplate = true
        let templateResident = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        templateResident.update(profile: profile, isActive: false, isResident: true)
        templateResident.setSourceIcon(templateIcon)
        XCTAssertTrue(templateResident.displayedIcon === templateIcon)
        XCTAssertEqual(templateResident.displayedIconTintColor, .labelColor)
        templateResident.setUnreadResponse(true)
        XCTAssertEqual(
            templateResident.displayedIconTintColor,
            TabAttentionStyle.dot.configuration(for: .red).foregroundColor
        )
        templateResident.update(profile: profile, isActive: true, isResident: false)
        XCTAssertEqual(templateResident.displayedIconTintColor, .tertiaryLabelColor)
        XCTAssertTrue(templateResident.isShowingUnreadResponse)
    }

    func testActiveIconContrastBackgroundAdaptsToAppearanceWithoutChangingBrandOrGeometry() {
        let profile = makeProfile(url: "https://www.google.com/")
        let tab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        tab.frame = NSRect(x: 0, y: 0, width: 220, height: 44)

        tab.appearance = NSAppearance(named: .darkAqua)
        tab.update(profile: profile, isActive: true, isResident: true)
        let activeWidth = tab.preferredWidth
        let blackBrandIcon = fixtureImage(color: .black)
        tab.setSourceIcon(blackBrandIcon)
        XCTAssertEqual(activeWidth, tab.preferredWidth)
        tab.layoutSubtreeIfNeeded()
        let darkIconFrame = tab.iconFrame
        XCTAssertTrue(tab.displayedIcon === blackBrandIcon)
        XCTAssertEqual(tab.displayedIconAlpha, 1, accuracy: 0.001)
        XCTAssertNotNil(tab.displayedIconContrastBackgroundColor)

        tab.update(profile: profile, isActive: false, isResident: true)
        tab.layoutSubtreeIfNeeded()
        XCTAssertNotNil(tab.displayedIconContrastBackgroundColor)
        XCTAssertEqual(tab.displayedIconAlpha, 1, accuracy: 0.001)
        XCTAssertTrue(tab.displayedIcon === blackBrandIcon)
        XCTAssertEqual(tab.iconFrame, darkIconFrame)
        let inactiveWidth = tab.preferredWidth
        XCTAssertNotEqual(activeWidth, inactiveWidth)

        tab.setResident(false)
        XCTAssertNil(tab.displayedIconContrastBackgroundColor)
        XCTAssertEqual(tab.displayedIconAlpha, 0.38, accuracy: 0.001)
        XCTAssertFalse(tab.displayedIcon === blackBrandIcon)
        tab.setHovered(true)
        XCTAssertEqual(tab.displayedIconAlpha, 0.60, accuracy: 0.001)
        XCTAssertLessThan(tab.displayedIconAlpha, 1)
        XCTAssertFalse(tab.displayedIcon === blackBrandIcon)

        tab.setHovered(false)
        tab.setResident(true)
        XCTAssertTrue(tab.displayedIcon === blackBrandIcon)
        XCTAssertEqual(tab.displayedIconAlpha, 1, accuracy: 0.001)
        XCTAssertNotNil(tab.displayedIconContrastBackgroundColor)

        let lightTab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, _ in })
        lightTab.appearance = NSAppearance(named: .aqua)
        lightTab.update(profile: profile, isActive: false, isResident: true)
        lightTab.setSourceIcon(blackBrandIcon)
        XCTAssertNil(lightTab.displayedIconContrastBackgroundColor)
        let whiteBrandIcon = fixtureImage(color: .white)
        lightTab.setSourceIcon(whiteBrandIcon)
        XCTAssertTrue(lightTab.displayedIcon === whiteBrandIcon)
        XCTAssertNotNil(lightTab.displayedIconContrastBackgroundColor)

        let multicolorIcon = NSImage(size: NSSize(width: 16, height: 16))
        multicolorIcon.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 16).fill()
        NSColor.systemYellow.setFill()
        NSRect(x: 8, y: 0, width: 8, height: 16).fill()
        multicolorIcon.unlockFocus()
        tab.setSourceIcon(multicolorIcon)
        tab.update(profile: profile, isActive: false, isResident: true)
        XCTAssertTrue(tab.displayedIcon === multicolorIcon)
        XCTAssertEqual(tab.displayedIconAlpha, 1, accuracy: 0.001)

        var faviconRequests = 0
        let noRefetchTab = ExternalWebAppTabView(slotID: UUID(), faviconLoader: { _, completion in
            faviconRequests += 1
            completion(nil)
        })
        noRefetchTab.update(profile: profile, isActive: false, isResident: false)
        noRefetchTab.update(profile: profile, isActive: true, isResident: true)
        noRefetchTab.update(profile: profile, isActive: false, isResident: false)
        XCTAssertEqual(faviconRequests, 1, "selection and residency changes must not request another favicon")
    }

    func testActiveConsumerRetriesAfterCooldownWithoutAnotherUIUpdate() async throws {
        let imageData = try fixtureImageData(color: .systemTeal)
        let retryGate = FaviconRetryGate()
        let loader = FaviconTestLoader { request, count in
            if count > 14 {
                return (imageData, Self.response(for: request, status: 200, mimeType: "image/png"))
            }
            return (Data(), Self.response(for: request, status: 404))
        }
        let provider = WebsiteFaviconProvider(
            dataLoader: { try await loader.load($0) },
            retryWaiter: { await retryGate.wait(for: $0) }
        )
        let url = try XCTUnwrap(URL(string: "https://chatgpt.example.test/c/654"))
        let consumerID = UUID()
        let firstFailure = expectation(description: "initial retry cycle fails")
        let recovered = expectation(description: "scheduled retry succeeds")
        var results: [NSImage?] = []
        provider.subscribe(for: url, consumerID: consumerID) { image in
            results.append(image)
            if image == nil {
                firstFailure.fulfill()
            } else {
                recovered.fulfill()
            }
        }

        await retryGate.waitUntilScheduled(1)
        XCTAssertEqual(retryGate.delays, [15])
        retryGate.resumeNext()
        await fulfillment(of: [firstFailure], timeout: 2)
        XCTAssertEqual(loader.requests.count, 14)

        await retryGate.waitUntilScheduled(2)
        XCTAssertEqual(retryGate.delays, [15, 120])
        retryGate.resumeNext()
        await fulfillment(of: [recovered], timeout: 2)

        XCTAssertEqual(loader.requests.count, 17)
        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results.last ?? nil)
        provider.cancel(consumerID: consumerID)
    }

    func testTabAndMenuBarKeepSameOriginSubscriptionsAndRejectAtoBtoAStaleCallbacks() throws {
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
        XCTAssertEqual(tabCompletions.count, 1)
        let tabImage = fixtureImage(color: .systemBlue)
        tabCompletions[0](tabImage)
        let successfulTabImage = tab.displayedIcon?.tiffRepresentation
        tab.update(profile: profile, isActive: true, isResident: true)
        XCTAssertEqual(tabCompletions.count, 1)
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
        XCTAssertEqual(menuCompletions.count, 1)
        let menuImage = fixtureImage(color: .systemGreen)
        menuCompletions[0](menuImage)
        let successfulMenuImage = statusItem.debugStatusButtonImageTIFF
        statusItem.setActiveWebApp(name: "ChatGPT", faviconURL: siteA)
        XCTAssertEqual(menuCompletions.count, 1)
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

    private func waitForDiagnostic(
        _ writer: RuntimeDiagnosticInMemoryWriter,
        matching predicate: ([RuntimeDiagnosticEvent]) -> Bool
    ) async {
        for _ in 0..<200 {
            if predicate(writer.events) { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for the expected favicon diagnostic event")
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
        let tiff = try XCTUnwrap(fixtureImage(color: color).tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func fixtureTransparentImageData() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16,
            pixelsHigh: 16,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill(using: .copy)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func fixtureSVGData() -> Data {
        Data(
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="#2563eb"/></svg>"##.utf8
        )
    }

    private func fixtureICOData(color: NSColor) throws -> Data {
        let png = try fixtureImageData(color: color)
        var data = Data([0, 0, 1, 0, 1, 0])
        data.append(contentsOf: [16, 16, 0, 0, 1, 0, 32, 0])
        let byteCount = UInt32(png.count)
        let imageOffset = UInt32(22)
        for value in [byteCount, imageOffset] {
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 24) & 0xff))
        }
        data.append(png)
        return data
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

@MainActor
private final class FaviconFetchGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            let ready = waiters
            waiters.removeAll()
            ready.forEach { $0.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard continuations.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
