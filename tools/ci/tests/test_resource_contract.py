"""Platform-neutral verification of FloatTabs Info.plist and referenced app icons."""
import json
import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INFO = ROOT / "FloatTabs/Info.plist"
ASSETS = ROOT / "FloatTabs/Resources/Assets.xcassets"


class FloatTabsResourceContractTests(unittest.TestCase):
    def test_info_plist_allows_webkit_only_http(self):
        with INFO.open("rb") as data:
            info = plistlib.load(data)
        ats = info.get("NSAppTransportSecurity", {})
        self.assertIs(ats.get("NSAllowsArbitraryLoadsInWebContent"), True)
        self.assertFalse(ats.get("NSAllowsArbitraryLoads", False))

    def test_all_referenced_app_icon_files_are_valid_png(self):
        manifests = list(ASSETS.rglob("*.appiconset/Contents.json"))
        self.assertTrue(manifests, "No application icon catalog found")
        for manifest in manifests:
            with self.subTest(manifest=manifest.as_posix()):
                info = json.loads(manifest.read_text(encoding="utf-8"))
                self.assertTrue(info.get("images"), "Icon manifest is empty")
                for entry in info["images"]:
                    filename = entry.get("filename")
                    if not filename:
                        continue
                    file = manifest.parent / filename
                    self.assertTrue(file.is_file(), str(file))
                    with file.open("rb") as data:
                        self.assertEqual(data.read(8), b"\x89PNG\r\n\x1a\n")
                    self.assertGreater(file.stat().st_size, 8)


if __name__ == "__main__":
    unittest.main()
