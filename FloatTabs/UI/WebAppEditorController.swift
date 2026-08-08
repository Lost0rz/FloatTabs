import AppKit

struct WebAppEditorValue {
    var name: String
    var url: URL
}

@MainActor
enum WebAppEditorController {
    static func presentAdd(
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: "Add Web App",
            actionTitle: "Add Web App",
            initialName: "",
            initialURL: "",
            attachedTo: window,
            completion: completion
        )
    }

    static func presentEdit(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: "Edit Web App",
            actionTitle: "Save",
            initialName: profile.name,
            initialURL: profile.homeURL.absoluteString,
            attachedTo: window,
            completion: completion
        )
    }

    static func presentRename(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Rename Web App"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: profile.name)
        field.placeholderString = "Name"
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(name.isEmpty ? nil : name)
        }
    }

    static func confirmRemove(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove \(profile.name)?"
        alert.informativeText = "The Web App slot will be removed. Shared WebKit website data, cookies, and sessions will not be cleared."
        alert.addButton(withTitle: "Remove Web App")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private static func presentEditor(
        title: String,
        actionTitle: String,
        initialName: String,
        initialURL: String,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: initialName)
        nameField.placeholderString = "Name"
        let urlField = NSTextField(string: initialURL)
        urlField.placeholderString = "https://example.com"

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let urlLabel = NSTextField(labelWithString: "URL")
        urlLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let stack = NSStackView(views: [nameLabel, nameField, urlLabel, urlField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.setFrameSize(NSSize(width: 360, height: 116))
        nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }

            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let url = WebAppURL.normalized(from: urlField.stringValue) else {
                presentValidationError(attachedTo: window)
                completion(nil)
                return
            }

            completion(WebAppEditorValue(name: name, url: url))
        }
    }

    private static func presentValidationError(attachedTo window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Enter a valid Web App"
        alert.informativeText = "Name is required. URL must be an http or https address, such as example.com or https://example.com."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}
