import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewFactoryTests: XCTestCase {
    func testStageZeroWebViewUsesPersistentWebsiteDataStore() {
        let webView = WebViewFactory.makeStageZeroWebView()
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
    }

    func testConfiguredScrollerIsCompletelyHiddenAtRest() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        WebViewFactory.configureHiddenScrollerStyle(scrollView)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    func testScrollerVisibilityCanBeEnabledOnlyForActiveAxis() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        WebViewFactory.configureHiddenScrollerStyle(scrollView)

        WebViewFactory.setScrollerVisibility(
            scrollView,
            vertical: true,
            horizontal: false
        )

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        WebViewFactory.configureHiddenScrollerStyle(scrollView)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }
}
