import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class UniversalWebActivityBridgeTests: XCTestCase {
    func testHostPolicyRecognizesKnownAISitesAndExcludesChatGPT() {
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("gemini.google.com"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("chat.deepseek.com"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("claude.ai"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("www.perplexity.ai"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("grok.com"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("kimi.moonshot.cn"))
        XCTAssertTrue(UniversalWebSitePolicy.isKnownAIHost("chat.qwen.ai"))
        XCTAssertFalse(UniversalWebSitePolicy.isKnownAIHost("chatgpt.com"))
        XCTAssertFalse(UniversalWebSitePolicy.isKnownAIHost("chat.openai.com"))

        XCTAssertFalse(UniversalWebSitePolicy.isSupportedUniversalURL(URL(string: "https://chatgpt.com/")))
        XCTAssertFalse(UniversalWebSitePolicy.isSupportedUniversalURL(URL(string: "https://chat.openai.com/")))
        XCTAssertFalse(UniversalWebSitePolicy.isSupportedUniversalURL(URL(string: "file:///tmp/test.html")))
        XCTAssertTrue(UniversalWebSitePolicy.isSupportedUniversalURL(URL(string: "https://gemini.google.com/")))
        XCTAssertTrue(UniversalWebSitePolicy.isSupportedUniversalURL(URL(string: "https://github.com/Lost0rz/FloatTabs")))
    }

    func testChatGPTStopLabelsIncludeLocalizedChineseVariants() {
        XCTAssertTrue(ChatGPTResponseIdentity.sharedDOMHelperSource.contains("\"停止生成\""))
        XCTAssertTrue(ChatGPTResponseIdentity.sharedDOMHelperSource.contains("\"停止响应\""))
        XCTAssertTrue(ChatGPTResponseIdentity.sharedDOMHelperSource.contains("\"重新生成\""))
    }

    func testUniversalAIStreamingProtectsLifecycleMarksUnreadAndRoutesNotificationToGroupAndSlot() throws {
        let repository = InMemoryUniversalTestRepository()
        let store = TabStore(repository: repository)
        let workGroup = try XCTUnwrap(store.createGroup(name: "Work"))
        let activeTab = try XCTUnwrap(
            store.add(
                name: "Docs",
                homeURL: URL(string: "https://example.com")!,
                targetGroupID: .some(nil)
            )
        )
        let deepSeekTab = try XCTUnwrap(
            store.add(
                name: "DeepSeek",
                homeURL: URL(string: "https://chat.deepseek.com/")!,
                targetGroupID: .some(workGroup.id)
            )
        )
        XCTAssertTrue(store.select(id: activeTab.id))

        let attention = WebAttentionCoordinator()
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in }
        )
        let controller = PanelController(
            tabStore: store,
            webViewPool: pool,
            attentionCoordinator: attention,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        var capturedNotifications: [(UUID, String?, String?, String?)] = []
        var soundCount = 0
        controller.onUniversalNotificationRequested = { slotID, title, preview, fallback in
            capturedNotifications.append((slotID, title, preview, fallback))
        }
        controller.onChatGPTGenerationCompleted = { _ in
            soundCount += 1
        }

        let bridge = UniversalWebActivityBridge(slotID: deepSeekTab.id) { slotID, event in
            controller.handleUniversalActivityEvent(slotID: slotID, event: event)
        }
        let deepSeekURL = URL(string: "https://chat.deepseek.com/")!

        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "baseline", "token": "tok-baseline-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: deepSeekURL
        ))
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "generation_started", "token": "tok-baseline-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: deepSeekURL
        ))
        XCTAssertTrue(attention.isAttentionProtected(deepSeekTab.id))

        XCTAssertTrue(bridge.acceptMessageBody(
            [
                "kind": "generation_finished",
                "token": "tok-baseline-1",
                "preview": "Here is the summary from DeepSeek.",
                "identity": "message:univ-ai-ds1"
            ],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: deepSeekURL
        ))

        XCTAssertFalse(attention.isAttentionProtected(deepSeekTab.id))
        XCTAssertTrue(controller.unreadResponseSlotIDs.contains(deepSeekTab.id))
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(capturedNotifications.count, 1)
        XCTAssertEqual(capturedNotifications[0].0, deepSeekTab.id)
        XCTAssertEqual(capturedNotifications[0].1, "Work · DeepSeek")
        XCTAssertEqual(capturedNotifications[0].2, "Here is the summary from DeepSeek.")

        XCTAssertTrue(controller.presentSlotFromCompletionNotification(deepSeekTab.id))
        XCTAssertEqual(store.activeGroupID, workGroup.id)
        XCTAssertEqual(store.activeTabID, deepSeekTab.id)
    }

    func testWebNotificationAndBadgeActivityBridgeRejectChatGPTAndDeliverUniversalUpdates() throws {
        let repository = InMemoryUniversalTestRepository()
        let store = TabStore(repository: repository)
        let youtube = try XCTUnwrap(
            store.add(name: "YouTube", homeURL: URL(string: "https://www.youtube.com/")!)
        )
        let activeDocs = try XCTUnwrap(
            store.add(name: "Docs", homeURL: URL(string: "https://example.com/")!)
        )
        XCTAssertTrue(store.select(id: activeDocs.id))

        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in }
        )
        let controller = PanelController(
            tabStore: store,
            webViewPool: pool,
            attentionCoordinator: WebAttentionCoordinator(),
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        var capturedNotifications: [(UUID, String?, String?, String?)] = []
        controller.onUniversalNotificationRequested = { slotID, title, preview, fallback in
            capturedNotifications.append((slotID, title, preview, fallback))
        }

        let bridge = UniversalWebActivityBridge(slotID: youtube.id) { slotID, event in
            controller.handleUniversalActivityEvent(slotID: slotID, event: event)
        }
        let youtubeURL = URL(string: "https://www.youtube.com/")!

        XCTAssertFalse(bridge.acceptMessageBody(
            ["kind": "web_notification", "title": "ChatGPT", "body": "Ignored"],
            handlerName: UniversalWebActivityBridge.notificationHandlerName,
            originURL: URL(string: "https://chatgpt.com/")!
        ))

        XCTAssertTrue(bridge.acceptMessageBody(
            [
                "kind": "web_notification",
                "title": "New Comment",
                "body": "@dev replied on your video",
                "tag": "yt-comment-42"
            ],
            handlerName: UniversalWebActivityBridge.notificationHandlerName,
            originURL: youtubeURL
        ))
        XCTAssertTrue(controller.unreadResponseSlotIDs.contains(youtube.id))
        XCTAssertEqual(capturedNotifications.count, 1)
        XCTAssertEqual(capturedNotifications[0].1, "YouTube — New Comment")
        XCTAssertEqual(capturedNotifications[0].2, "@dev replied on your video")

        // Stale or unknown document token for activity events must be rejected
        XCTAssertFalse(bridge.acceptMessageBody(
            ["kind": "badge_activity", "token": "stale-token-999", "count": 2, "title": "YouTube"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: youtubeURL
        ))

        // Clearing badge clears unread automatically
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "baseline", "token": "tok-yt-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: youtubeURL
        ))
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "activity_cleared", "token": "tok-yt-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: youtubeURL
        ))
        XCTAssertFalse(controller.unreadResponseSlotIDs.contains(youtube.id))
    }

    func testActivityScriptExposesW3CNotificationAndExcludesInitialBadgeBaseline() async throws {
        let webView = WebViewFactory.makeWebView(
            renderingProfile: .canonicalDefault,
            websiteDataStore: .nonPersistent(),
            configureUserContentController: { controller in
                controller.addUserScript(
                    WKUserScript(
                        source: UniversalWebActivityBridge.notificationScriptSource,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true,
                        in: UniversalWebActivityBridge.notificationContentWorld
                    )
                )
            }
        )

        class NavWaiter: NSObject, WKNavigationDelegate {
            var continuation: CheckedContinuation<Void, Never>?
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                continuation?.resume()
                continuation = nil
            }
        }
        let waiter = NavWaiter()
        webView.navigationDelegate = waiter
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                "<!doctype html><html><head><title>(3) YouTube</title></head><body>ok</body></html>",
                baseURL: URL(string: "https://www.youtube.com/")!
            )
        }
        let permission = try await webView.evaluateJavaScript("Notification.permission") as? String
        XCTAssertEqual(permission, "granted")
    }

    func testNavigationCommitAndInstantBackResyncReestablishDocumentTokenInLiveWebView() async throws {
        let repository = InMemoryUniversalTestRepository()
        let store = TabStore(repository: repository)
        let geminiTab = try XCTUnwrap(
            store.add(name: "Gemini", homeURL: URL(string: "https://gemini.google.com/")!)
        )
        let activeDocs = try XCTUnwrap(
            store.add(name: "Docs", homeURL: URL(string: "https://example.com/")!)
        )
        XCTAssertTrue(store.select(id: activeDocs.id))

        let attention = WebAttentionCoordinator()
        let controller = PanelController(
            tabStore: store,
            webViewPool: WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in }),
            attentionCoordinator: attention,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        let bridge = UniversalWebActivityBridge(slotID: geminiTab.id) { slotID, event in
            controller.handleUniversalActivityEvent(slotID: slotID, event: event)
        }

        let webView = WebViewFactory.makeWebView(
            renderingProfile: .canonicalDefault,
            websiteDataStore: .nonPersistent(),
            configureUserContentController: { ucc in
                bridge.install(into: ucc)
            }
        )
        webView.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        bridge.attach(to: webView)

        class NavDelegate: NSObject, WKNavigationDelegate {
            var onCommit: (() -> Void)?
            var continuation: CheckedContinuation<Void, Never>?
            func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
                onCommit?()
            }
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
                continuation?.resume()
                continuation = nil
            }
        }
        let nav = NavDelegate()
        let committedURL = URL(string: "https://gemini.google.com/app")!
        nav.onCommit = {
            bridge.handleNavigationCommit(committedURL: committedURL)
        }
        webView.navigationDelegate = nav
        await withCheckedContinuation { continuation in
            nav.continuation = continuation
            webView.loadHTMLString(
                "<!doctype html><html><head><title>Gemini</title></head><body><main><div id='chat'></div></main></body></html>",
                baseURL: committedURL
            )
        }

        for _ in 0..<20 where !bridge.hasActiveDocumentTokenForTesting {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(bridge.hasActiveDocumentTokenForTesting)

        bridge.handleInstantBackActivation(committedURL: committedURL)
        for _ in 0..<20 where !bridge.hasActiveDocumentTokenForTesting {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(bridge.hasActiveDocumentTokenForTesting)

        _ = try await webView.evaluateJavaScript(
            """
            const btn = document.createElement('button');
            btn.setAttribute('aria-label', 'Stop generating');
            btn.style.width = '32px';
            btn.style.height = '32px';
            btn.textContent = 'Stop';
            document.getElementById('chat').appendChild(btn);
            true;
            """
        )
        for _ in 0..<40 where !attention.isAttentionProtected(geminiTab.id) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(attention.isAttentionProtected(geminiTab.id))
    }

    func testConsecutiveBadgeIncrementsSuppressDuplicateSoundAndClearWithdrawsNotification() throws {
        let repository = InMemoryUniversalTestRepository()
        let store = TabStore(repository: repository)
        let xTab = try XCTUnwrap(
            store.add(name: "X", homeURL: URL(string: "https://x.com/home")!)
        )
        let activeDocs = try XCTUnwrap(
            store.add(name: "Docs", homeURL: URL(string: "https://example.com/")!)
        )
        XCTAssertTrue(store.select(id: activeDocs.id))

        let controller = PanelController(
            tabStore: store,
            webViewPool: WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in }),
            attentionCoordinator: WebAttentionCoordinator(),
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        var capturedNotifications: [(UUID, String?, String?, String?)] = []
        var withdrawnSlotIDs: [UUID] = []
        var soundCount = 0
        controller.onUniversalNotificationRequested = { slotID, title, preview, fallback in
            capturedNotifications.append((slotID, title, preview, fallback))
        }
        controller.onUnreadSlotAcknowledged = { slotID in
            withdrawnSlotIDs.append(slotID)
        }
        controller.onChatGPTGenerationCompleted = { _ in
            soundCount += 1
        }

        let bridge = UniversalWebActivityBridge(slotID: xTab.id) { slotID, event in
            controller.handleUniversalActivityEvent(slotID: slotID, event: event)
        }
        let xURL = URL(string: "https://x.com/home")!
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "baseline", "token": "tok-x-badge-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: xURL
        ))
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "badge_activity", "token": "tok-x-badge-1", "count": 1, "title": "Home / X"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: xURL
        ))
        XCTAssertTrue(controller.unreadResponseSlotIDs.contains(xTab.id))
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(capturedNotifications.count, 1)

        // Subsequent passive badge increment while already unread must update without resounding.
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "badge_activity", "token": "tok-x-badge-1", "count": 2, "title": "Home / X"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: xURL
        ))
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(capturedNotifications.count, 1)

        // Clearing site badge clears unread even while visible and withdraws stale notifications.
        controller.debugSetPresentationFactOverride(slotID: xTab.id, presentationFact: true)
        XCTAssertTrue(bridge.acceptMessageBody(
            ["kind": "activity_cleared", "token": "tok-x-badge-1"],
            handlerName: UniversalWebActivityBridge.activityHandlerName,
            originURL: xURL
        ))
        XCTAssertFalse(controller.unreadResponseSlotIDs.contains(xTab.id))
        XCTAssertEqual(withdrawnSlotIDs, [xTab.id])
    }
}

private final class InMemoryUniversalTestRepository: ProfileRepositoryProtocol {
    var state = StoredWebAppState.empty
    func load() throws -> StoredWebAppState { state }
    func save(_ state: StoredWebAppState) throws { self.state = state }
}
