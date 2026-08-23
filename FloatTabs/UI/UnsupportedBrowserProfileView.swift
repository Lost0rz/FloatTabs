import AppKit

/// Non-Web presentation for a Slot whose persisted custom Profile cannot be
/// instantiated on the current macOS version.
///
/// This view deliberately contains no WebKit or Profile mutation controls. The
/// existing Profile menu remains the explicit reassignment authority.
final class UnsupportedBrowserProfileView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Profile Requires macOS 14 or Later")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stackView: NSStackView

    private(set) var displayedProfileName: String?

    var titleText: String {
        titleLabel.stringValue
    }

    var detailText: String {
        detailLabel.stringValue
    }

    override init(frame frameRect: NSRect) {
        stackView = NSStackView(views: [titleLabel, detailLabel])
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(profileName: String, defaultProfileName: String = "Default") {
        displayedProfileName = profileName
        let quotedName = "\u{201C}\(profileName)\u{201D}"
        detailLabel.stringValue = "\(quotedName) is still assigned to this Web App. This Profile requires macOS 14 or later. FloatTabs did not open it with \(defaultProfileName). To use this Web App on this Mac, choose Profile > \(defaultProfileName) to explicitly reassign this Slot."
    }
}
