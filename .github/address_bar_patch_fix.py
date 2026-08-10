from pathlib import Path

path = Path("FloatTabsTests/AppCommandControllerTests.swift")
text = path.read_text()
replacements = [
    ("AddressBarOverlayView", "AddressOverlayView"),
    ("presentedAddressBarOverlay", "presentedAddressOverlay"),
]
for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{old}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)
path.write_text(text)
