import Foundation

enum WebsiteMode: String, Codable, CaseIterable {
    case desktop
    case mobile

    var displayName: String {
        switch self {
        case .desktop: "Desktop"
        case .mobile: "Mobile"
        }
    }
}

enum BrowserIdentity: String, Codable, CaseIterable {
    case automatic
    case macosSafari
    case macosChrome
    case windowsChrome
    case windowsEdge
    case linuxChrome
    case iphoneSafari
    case iphoneChrome
    case androidChrome
    case custom

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .macosSafari: "macOS Safari"
        case .macosChrome: "macOS Chrome"
        case .windowsChrome: "Windows Chrome"
        case .windowsEdge: "Windows Edge"
        case .linuxChrome: "Linux Chrome"
        case .iphoneSafari: "iPhone Safari"
        case .iphoneChrome: "iPhone Chrome"
        case .androidChrome: "Android Chrome"
        case .custom: "Custom User Agent"
        }
    }
}

enum SimpleViewportPreset: String, Codable, CaseIterable {
    case small
    case medium
    case large
    case wide
    case custom

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .wide: "Wide"
        case .custom: "Custom"
        }
    }

    /// Visible FloatTabs viewport sizes are product experience tiers, not
    /// device emulation sizes. Their spacing is intentionally large enough to
    /// produce materially different reading/browsing surfaces.
    var size: CGSize? {
        switch self {
        case .small: CGSize(width: 420, height: 760)
        case .medium: CGSize(width: 600, height: 820)
        case .large: CGSize(width: 820, height: 850)
        case .wide: CGSize(width: 1080, height: 850)
        case .custom: nil
        }
    }

    var menuTitle: String {
        guard let size else { return displayName }
        return "\(displayName)  \(Int(size.width)) × \(Int(size.height))"
    }

    static func matching(_ size: CGSize, tolerance: CGFloat = 0.5) -> SimpleViewportPreset? {
        allCases.first { preset in
            guard let candidate = preset.size else { return false }
            return abs(candidate.width - size.width) <= tolerance
                && abs(candidate.height - size.height) <= tolerance
        }
    }
}

enum DeviceOrientation: String, Codable, CaseIterable {
    case portrait
    case landscape

    var displayName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }
}

enum DevicePresetClass: String, Codable {
    case phone
    case tablet
}

struct DevicePreset: Identifiable, Equatable {
    let id: String
    let displayName: String
    let groupName: String
    let portraitSize: CGSize
    let deviceClass: DevicePresetClass
    let referenceDPR: CGFloat
    let suggestedBrowserIdentity: BrowserIdentity

    func size(for orientation: DeviceOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            portraitSize
        case .landscape:
            CGSize(width: portraitSize.height, height: portraitSize.width)
        }
    }

    var menuTitle: String {
        "\(displayName)  \(Int(portraitSize.width)) × \(Int(portraitSize.height))"
    }
}

enum DevicePresetCatalog {
    static let all: [DevicePreset] = [
        DevicePreset(
            id: "iphone-compact",
            displayName: "iPhone SE / Compact",
            groupName: "iPhone",
            portraitSize: CGSize(width: 375, height: 667),
            deviceClass: .phone,
            referenceDPR: 2,
            suggestedBrowserIdentity: .iphoneSafari
        ),
        DevicePreset(
            id: "iphone-16e",
            displayName: "iPhone 16e",
            groupName: "iPhone",
            portraitSize: CGSize(width: 390, height: 844),
            deviceClass: .phone,
            referenceDPR: 3,
            suggestedBrowserIdentity: .iphoneSafari
        ),
        DevicePreset(
            id: "iphone-17-pro",
            displayName: "iPhone 17 / 17 Pro",
            groupName: "iPhone",
            portraitSize: CGSize(width: 402, height: 874),
            deviceClass: .phone,
            referenceDPR: 3,
            suggestedBrowserIdentity: .iphoneSafari
        ),
        DevicePreset(
            id: "iphone-air",
            displayName: "iPhone Air",
            groupName: "iPhone",
            portraitSize: CGSize(width: 420, height: 912),
            deviceClass: .phone,
            referenceDPR: 3,
            suggestedBrowserIdentity: .iphoneSafari
        ),
        DevicePreset(
            id: "iphone-17-pro-max",
            displayName: "iPhone 17 Pro Max",
            groupName: "iPhone",
            portraitSize: CGSize(width: 440, height: 956),
            deviceClass: .phone,
            referenceDPR: 3,
            suggestedBrowserIdentity: .iphoneSafari
        ),
        DevicePreset(
            id: "android-standard",
            displayName: "Android Standard",
            groupName: "Android",
            portraitSize: CGSize(width: 412, height: 924),
            deviceClass: .phone,
            referenceDPR: 2.625,
            suggestedBrowserIdentity: .androidChrome
        ),
        DevicePreset(
            id: "android-large",
            displayName: "Android Large",
            groupName: "Android",
            portraitSize: CGSize(width: 448, height: 997),
            deviceClass: .phone,
            referenceDPR: 3,
            suggestedBrowserIdentity: .androidChrome
        ),
        DevicePreset(
            id: "ipad-mini",
            displayName: "iPad mini",
            groupName: "iPad",
            portraitSize: CGSize(width: 744, height: 1133),
            deviceClass: .tablet,
            referenceDPR: 2,
            suggestedBrowserIdentity: .macosSafari
        ),
        DevicePreset(
            id: "ipad-air-11",
            displayName: "iPad Air 11\"",
            groupName: "iPad",
            portraitSize: CGSize(width: 820, height: 1180),
            deviceClass: .tablet,
            referenceDPR: 2,
            suggestedBrowserIdentity: .macosSafari
        ),
        DevicePreset(
            id: "ipad-pro-13",
            displayName: "iPad Pro 13\"",
            groupName: "iPad",
            portraitSize: CGSize(width: 1032, height: 1376),
            deviceClass: .tablet,
            referenceDPR: 2,
            suggestedBrowserIdentity: .macosSafari
        ),
    ]

    static func preset(id: String?) -> DevicePreset? {
        guard let id else { return nil }
        return all.first(where: { $0.id == id })
    }
}

enum ZoomSteps {
    static let values: [CGFloat] = [
        0.50, 0.60, 0.67, 0.75, 0.80, 0.90, 1.00,
        1.10, 1.25, 1.33, 1.50, 1.75, 2.00,
    ]

    static func nearest(to proposed: CGFloat) -> CGFloat {
        values.min(by: { abs($0 - proposed) < abs($1 - proposed) }) ?? 1.0
    }

    static func nextLarger(after current: CGFloat) -> CGFloat {
        values.first(where: { $0 > current + 0.001 }) ?? values.last ?? 1.0
    }

    static func nextSmaller(before current: CGFloat) -> CGFloat {
        values.reversed().first(where: { $0 < current - 0.001 }) ?? values.first ?? 1.0
    }

    static func percentageText(for zoom: CGFloat) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }
}

struct WebRenderingProfile: Codable, Equatable {
    static let minimumViewportSize = CGSize(width: 320, height: 400)

    var websiteMode: WebsiteMode
    var browserIdentity: BrowserIdentity
    var customUserAgent: String?
    var sizePreset: SimpleViewportPreset
    var devicePresetID: String?
    var orientation: DeviceOrientation
    var viewportWidth: CGFloat
    var viewportHeight: CGFloat
    var zoom: CGFloat

    static let canonicalDefault = WebRenderingProfile(
        websiteMode: .desktop,
        browserIdentity: .automatic,
        customUserAgent: nil,
        sizePreset: .medium,
        devicePresetID: nil,
        orientation: .portrait,
        viewportWidth: 600,
        viewportHeight: 820,
        zoom: 1.0
    )

    var viewportSize: CGSize {
        CGSize(width: viewportWidth, height: viewportHeight)
    }

    var devicePreset: DevicePreset? {
        DevicePresetCatalog.preset(id: devicePresetID)
    }

    /// Website Mode and Browser Identity are independent product layers.
    /// Automatic follows the requested Website Mode, while an explicit identity
    /// remains independent and always wins.
    var effectiveWebsiteMode: WebsiteMode {
        websiteMode
    }

    var effectiveBrowserIdentity: BrowserIdentity {
        switch browserIdentity {
        case .automatic:
            return websiteMode == .desktop ? .macosSafari : .iphoneSafari
        default:
            return browserIdentity
        }
    }

    func normalized() -> WebRenderingProfile {
        var copy = self
        copy.viewportWidth = max(viewportWidth, Self.minimumViewportSize.width)
        copy.viewportHeight = max(viewportHeight, Self.minimumViewportSize.height)
        copy.zoom = ZoomSteps.nearest(to: zoom)

        if let custom = copy.customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            copy.customUserAgent = custom
        } else {
            copy.customUserAgent = nil
            if copy.browserIdentity == .custom {
                copy.browserIdentity = .automatic
            }
        }

        if copy.browserIdentity != .custom {
            copy.customUserAgent = nil
        }

        if let device = DevicePresetCatalog.preset(id: copy.devicePresetID) {
            copy.sizePreset = .custom
            let size = device.size(for: copy.orientation)
            copy.viewportWidth = size.width
            copy.viewportHeight = size.height
        } else {
            copy.devicePresetID = nil
            if let presetSize = copy.sizePreset.size {
                copy.viewportWidth = presetSize.width
                copy.viewportHeight = presetSize.height
            }
        }

        return copy
    }

    func settingWebsiteMode(_ mode: WebsiteMode) -> WebRenderingProfile {
        var copy = self
        copy.websiteMode = mode
        return copy.normalized()
    }

    func settingBrowserIdentity(
        _ identity: BrowserIdentity,
        customUserAgent: String? = nil
    ) -> WebRenderingProfile {
        var copy = self
        copy.browserIdentity = identity
        copy.customUserAgent = identity == .custom ? customUserAgent : nil
        return copy.normalized()
    }

    func settingSimplePreset(_ preset: SimpleViewportPreset) -> WebRenderingProfile {
        var copy = self
        copy.sizePreset = preset
        copy.devicePresetID = nil
        if let size = preset.size {
            copy.viewportWidth = size.width
            copy.viewportHeight = size.height
            copy.orientation = size.width > size.height ? .landscape : .portrait
        }
        return copy.normalized()
    }

    func settingDevicePreset(
        id: String,
        orientation: DeviceOrientation = .portrait
    ) -> WebRenderingProfile {
        guard let device = DevicePresetCatalog.preset(id: id) else { return self }
        var copy = self
        copy.sizePreset = .custom
        copy.devicePresetID = device.id
        copy.orientation = orientation
        let size = device.size(for: orientation)
        copy.viewportWidth = size.width
        copy.viewportHeight = size.height
        return copy.normalized()
    }

    func settingOrientation(_ orientation: DeviceOrientation) -> WebRenderingProfile {
        var copy = self
        if let device = copy.devicePreset {
            copy.orientation = orientation
            let size = device.size(for: orientation)
            copy.viewportWidth = size.width
            copy.viewportHeight = size.height
        } else if copy.orientation != orientation {
            copy.orientation = orientation
            swap(&copy.viewportWidth, &copy.viewportHeight)
            copy.sizePreset = .custom
        }
        return copy.normalized()
    }

    func settingViewport(_ size: CGSize) -> WebRenderingProfile {
        var copy = self
        copy.sizePreset = .custom
        copy.devicePresetID = nil
        copy.viewportWidth = max(size.width, Self.minimumViewportSize.width)
        copy.viewportHeight = max(size.height, Self.minimumViewportSize.height)
        copy.orientation = copy.viewportWidth > copy.viewportHeight ? .landscape : .portrait
        return copy.normalized()
    }

    func settingZoom(_ zoom: CGFloat) -> WebRenderingProfile {
        var copy = self
        copy.zoom = ZoomSteps.nearest(to: zoom)
        return copy.normalized()
    }

    func requiresWebViewRebuild(comparedTo previous: WebRenderingProfile) -> Bool {
        let current = normalized()
        let old = previous.normalized()
        return current.effectiveBrowserIdentity != old.effectiveBrowserIdentity
            || current.effectiveWebsiteMode != old.effectiveWebsiteMode
            || current.customUserAgent != old.customUserAgent
    }

    private enum CodingKeys: String, CodingKey {
        case websiteMode
        case browserIdentity
        case customUserAgent
        case sizePreset
        case devicePresetID
        case orientation
        case viewportWidth
        case viewportHeight
        case zoom

        // Stage 2 / original Stage 3 compatibility fields.
        case browserCompatibility
        case contentMode
    }

    private enum LegacyBrowserCompatibility: String, Codable {
        case safari
        case chrome
    }

    private enum LegacyContentMode: String, Codable {
        case responsive
        case desktop
        case mobile
    }

    init(
        websiteMode: WebsiteMode,
        browserIdentity: BrowserIdentity,
        customUserAgent: String?,
        sizePreset: SimpleViewportPreset,
        devicePresetID: String?,
        orientation: DeviceOrientation,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat,
        zoom: CGFloat
    ) {
        self.websiteMode = websiteMode
        self.browserIdentity = browserIdentity
        self.customUserAgent = customUserAgent
        self.sizePreset = sizePreset
        self.devicePresetID = devicePresetID
        self.orientation = orientation
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.zoom = zoom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decodeIfPresent(CGFloat.self, forKey: .viewportWidth) ?? 600
        let height = try container.decodeIfPresent(CGFloat.self, forKey: .viewportHeight) ?? 820
        let decodedZoom = try container.decodeIfPresent(CGFloat.self, forKey: .zoom) ?? 1.0

        if let newMode = try container.decodeIfPresent(WebsiteMode.self, forKey: .websiteMode) {
            websiteMode = newMode
            browserIdentity = try container.decodeIfPresent(BrowserIdentity.self, forKey: .browserIdentity)
                ?? .automatic
            customUserAgent = try container.decodeIfPresent(String.self, forKey: .customUserAgent)
            sizePreset = try container.decodeIfPresent(SimpleViewportPreset.self, forKey: .sizePreset)
                ?? SimpleViewportPreset.matching(CGSize(width: width, height: height))
                ?? .custom
            devicePresetID = try container.decodeIfPresent(String.self, forKey: .devicePresetID)
            orientation = try container.decodeIfPresent(DeviceOrientation.self, forKey: .orientation)
                ?? (width > height ? .landscape : .portrait)
        } else {
            let legacyBrowser = try container.decodeIfPresent(
                LegacyBrowserCompatibility.self,
                forKey: .browserCompatibility
            ) ?? .safari
            let legacyMode = try container.decodeIfPresent(
                LegacyContentMode.self,
                forKey: .contentMode
            ) ?? .responsive

            websiteMode = legacyMode == .mobile ? .mobile : .desktop
            switch (legacyBrowser, legacyMode) {
            case (.safari, .mobile): browserIdentity = .iphoneSafari
            case (.safari, _): browserIdentity = .macosSafari
            case (.chrome, .mobile): browserIdentity = .iphoneChrome
            case (.chrome, _): browserIdentity = .macosChrome
            }
            customUserAgent = nil
            sizePreset = SimpleViewportPreset.matching(CGSize(width: width, height: height)) ?? .custom
            devicePresetID = nil
            orientation = width > height ? .landscape : .portrait
        }

        viewportWidth = width
        viewportHeight = height
        zoom = decodedZoom
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        let profile = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile.websiteMode, forKey: .websiteMode)
        try container.encode(profile.browserIdentity, forKey: .browserIdentity)
        try container.encodeIfPresent(profile.customUserAgent, forKey: .customUserAgent)
        try container.encode(profile.sizePreset, forKey: .sizePreset)
        try container.encodeIfPresent(profile.devicePresetID, forKey: .devicePresetID)
        try container.encode(profile.orientation, forKey: .orientation)
        try container.encode(profile.viewportWidth, forKey: .viewportWidth)
        try container.encode(profile.viewportHeight, forKey: .viewportHeight)
        try container.encode(profile.zoom, forKey: .zoom)
    }
}
