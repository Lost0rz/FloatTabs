from pathlib import Path

panel = Path("FloatTabs/Panel/PanelController.swift")
text = panel.read_text(encoding="utf-8")
text = text.replace(
    "            preferencesStore.followPreferredSize: true,\n",
    "            followPreferredSize: true,\n"
)
panel.write_text(text, encoding="utf-8")

settings = Path("FloatTabs/UI/GlobalSettingsController.swift")
text = settings.read_text(encoding="utf-8")
old = '''                    detail: "FloatTabs configuration was restored. A rollback backup was saved at:
\\(rollbackURL.path)"
'''
new = r'''                    detail: "FloatTabs configuration was restored. A rollback backup was saved at:\n\(rollbackURL.path)"
'''
if old not in text:
    raise RuntimeError("restore success detail string was not found")
settings.write_text(text.replace(old, new, 1), encoding="utf-8")
