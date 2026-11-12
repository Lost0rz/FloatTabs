import fnmatch
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CATALOG = json.loads((ROOT / ".github/ci-capabilities.json").read_text(encoding="utf-8"))


def selecting(path):
    return [
        entry["id"]
        for entry in CATALOG["tests"]
        if any(fnmatch.fnmatchcase(path, glob) for glob in entry["paths"])
    ]


class FloatTabsCapabilityContractTests(unittest.TestCase):
    def test_catalog_is_portable_and_fails_closed_for_unknown_sources(self):
        self.assertEqual(CATALOG["contract"], "EG_CI_CAPABILITIES_V1")
        self.assertFalse(CATALOG["fallback_satisfies_ready"])
        self.assertEqual(CATALOG["fallback_tests"], ["ci-contracts"])

    def test_all_current_product_and_test_swift_files_have_a_lane(self):
        for directory in ("FloatTabs", "FloatTabsTests"):
            for file in (ROOT / directory).rglob("*.swift"):
                rel = file.relative_to(ROOT).as_posix()
                with self.subTest(rel):
                    self.assertTrue(selecting(rel), rel)

    def test_localized_source_changes_do_not_select_all_xctests(self):
        self.assertEqual(selecting("FloatTabs/Web/SlotLifecycleCoordinator.swift"), ["swift-runtime"])
        self.assertEqual(selecting("FloatTabs/Web/ChatGPTAttentionBridge.swift"), ["swift-attention"])
        self.assertEqual(selecting("FloatTabs/Diagnostics/RuntimeDiagnostics.swift"), ["swift-diagnostics"])
        self.assertEqual(selecting("FloatTabs/Storage/WebsiteCacheCleanupService.swift"), ["swift-storage"])
        self.assertEqual(selecting("FloatTabs/UI/ExternalTabRail.swift"), ["swift-ui"])

    def test_project_and_release_boundaries_select_integration(self):
        self.assertIn("swift-integration", selecting("FloatTabs.xcodeproj/project.pbxproj"))
        self.assertIn("swift-integration", selecting("tools/release/build_dmg.sh"))
        self.assertEqual(selecting(".github/ci-capabilities.json"), ["ci-contracts"])

    def test_runner_safety_and_explicit_test_selection(self):
        for test in CATALOG["tests"]:
            with self.subTest(test=test["id"]):
                self.assertLessEqual(len(test["command"]), 40)
                if test["id"].startswith("swift-"):
                    self.assertEqual(test["runner"], ["self-hosted", "macOS", "ARM64", "mac-mini-ci"])
                    self.assertFalse(test.get("fork_safe", False))
                if test.get("fork_safe", False):
                    self.assertNotIn("self-hosted", test["runner"])

    def test_current_xctest_groups_use_only_testing_filters(self):
        for test in CATALOG["tests"]:
            if test["id"].startswith("swift-") and test["id"] != "swift-integration":
                with self.subTest(lane=test["id"]):
                    self.assertEqual(test["command"][0], "xcodebuild")
                    self.assertTrue(any(x.startswith("-only-testing:FloatTabsTests/") for x in test["command"]))


if __name__ == "__main__":
    unittest.main()
