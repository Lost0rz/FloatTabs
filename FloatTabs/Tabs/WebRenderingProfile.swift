import Foundation

enum BrowserCompatibility: String, Codable, CaseIterable {
    case safari
    case chrome
}

enum WebContentMode: String, Codable, CaseIterable {
    case responsive
    case desktop
    case mobile
}

struct WebRenderingProfile: Codable, Equatable {
    var browserCompatibility: BrowserCompatibility
    var contentMode: WebContentMode
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var zoom: CGFloat

    static let canonicalDefault = WebRenderingProfile(
        browserCompatibility: .safari,
        contentMode: .responsive,
        viewportWidth: 430,
        viewportHeight: 820,
        zoom: 1.0
    )
}
