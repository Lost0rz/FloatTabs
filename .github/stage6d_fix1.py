from pathlib import Path

path = Path("FloatTabs/Panel/PanelController.swift")
text = path.read_text(encoding="utf-8")
old = """        case .reload:\n            reloadActiveSlot()\n\n        case .togglePin:\n"""
new = """        case .reload:\n            reloadActiveSlot()\n\n        case .settings:\n            onOpenGlobalSettings?()\n\n        case .togglePin:\n"""
if text.count(old) != 1:
    raise RuntimeError("PanelController settings switch insertion point not found exactly once")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
