from pathlib import Path

path = Path('.github/pr17_preferences_followup.py')
source = path.read_text()
old_helper = '''def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)
'''
new_helper = '''def replace_once(text, old, new, label):
    count = text.count(old)
    if label == "border appearance functions" and count == 2:
        # The generic skeleton appears in PanelRootView and another later view.
        # Defer this insertion to the scoped post-processing below.
        return text
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)
'''
if source.count(old_helper) != 1:
    raise SystemExit('replace_once helper shape changed unexpectedly')
source = source.replace(old_helper, new_helper, 1)
exec(compile(source, str(path), 'exec'))

# AppPreferencesStore: CharacterSet has no hexadecimalDigits convenience on the
# supported macOS SDK. Use an explicit ASCII hexadecimal set.
prefs_path = Path('FloatTabs/Persistence/AppPreferencesStore.swift')
prefs = prefs_path.read_text()
old_hex = '''        guard body.count == 6 || body.count == 8,
              body.unicodeScalars.allSatisfy({ CharacterSet.hexadecimalDigits.contains($0) }) else {
            return nil
        }
'''
new_hex = '''        let validHex = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard body.count == 6 || body.count == 8,
              body.unicodeScalars.allSatisfy({ validHex.contains($0) }) else {
            return nil
        }
'''
if prefs.count(old_hex) != 1:
    raise SystemExit('hex validation shape changed unexpectedly')
prefs_path.write_text(prefs.replace(old_hex, new_hex, 1))

# WebViewContainer: insert theme application methods only inside
# PanelInteractionBorderView. This avoids similarly shaped hit-test blocks in
# other shell views.
container_path = Path('FloatTabs/Web/WebViewContainer.swift')
container = container_path.read_text()
class_start = container.index('final class PanelInteractionBorderView: NSView {')
class_end = container.index('/// Four-way movement cursor', class_start)
segment = container[class_start:class_end]
anchor = '''    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
'''
methods = '''    override var isOpaque: Bool { false }

    func apply(theme: PanelBorderTheme, customColor: NSColor) {
        borderTheme = theme
        customBorderColor = customColor
        applyBorderAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderAppearance()
    }

    private func applyBorderAppearance() {
        gradientLayer.removeAnimation(forKey: "FloatTabs.interactionBorderFlow")

        if borderTheme == .rainbow {
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            let palettes = Self.flowPalettes
            gradientLayer.colors = palettes.first
            gradientLayer.locations = [0, 0.22, 0.48, 0.74, 1]

            let flow = CAKeyframeAnimation(keyPath: "colors")
            flow.values = palettes
            flow.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            flow.duration = 3.2
            flow.repeatCount = .infinity
            flow.calculationMode = .linear
            gradientLayer.add(flow, forKey: "FloatTabs.interactionBorderFlow")
        } else {
            let color = borderTheme.solidColor ?? customBorderColor
            gradientLayer.type = .axial
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.colors = [color.cgColor, color.cgColor]
            gradientLayer.locations = [0, 1]
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
'''
if segment.count(anchor) != 1:
    raise SystemExit(f'PanelInteractionBorderView anchor mismatch: {segment.count(anchor)}')
segment = segment.replace(anchor, methods, 1)
container = container[:class_start] + segment + container[class_end:]
container_path.write_text(container)
