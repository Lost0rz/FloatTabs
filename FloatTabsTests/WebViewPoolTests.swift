import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewPoolTests: XCTestCase {
    func testDifferentSlotIDsReceiveDifferentWebViews() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")

        let firstView = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        XCTAssertFalse(firstView === secondView)
        XCTAssertEqual(pool.count, 2)
    }

    func testSameSlotIDReusesSameWebViewInstance() {
        let pool = makePool()
        let profile = makeProfile(name: "A")

        let first = pool.webView(for: profile)
        let second = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(pool.count, 1)
    }

    func testPooledWebViewsUsePersistentWebsiteDataStore() {
        let pool = makePool()
        let webView = pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
    }

    func testRemovingOneSlotDoesNotAffectOtherWebViewIdentity() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        pool.remove(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeProfile(name: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com")!
        )
    }
}
