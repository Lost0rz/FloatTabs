import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MACOS_CI = (REPOSITORY_ROOT / ".github/workflows/macos-ci.yml").read_text(encoding="utf-8")
QA_DMG = (REPOSITORY_ROOT / ".github/workflows/qa-dmg.yml").read_text(encoding="utf-8")
BENCHMARK = (REPOSITORY_ROOT / ".github/workflows/benchmark-tool-ci.yml").read_text(encoding="utf-8")
CAPABILITIES = json.loads((REPOSITORY_ROOT / ".github/ci-capabilities.json").read_text(encoding="utf-8"))


class GovernedCIWorkflowContractTests(unittest.TestCase):
    def test_pr_and_explicit_manual_triggers_without_auto_main_full_test(self):
        header = MACOS_CI.split("jobs:", 1)[0]
        self.assertIn("  pull_request:", header)
        self.assertIn("  workflow_dispatch:", header)
        self.assertNotIn("  push:", header)
        self.assertNotIn("    paths:", header)

    def test_shared_router_is_pinned_and_only_accepted_catalog_is_used(self):
        self.assertIn("uses: Lost0rz/Engineering-Governance/.github/workflows/ci-router-reusable.yml@v0.10.0", MACOS_CI)
        self.assertIn("capabilities_path: .github/ci-capabilities.json", MACOS_CI)
        self.assertIn("github.event.pull_request.draft == false", MACOS_CI)
        self.assertNotIn("classify_macos_ci_scope.py", MACOS_CI)
        self.assertNotIn("xcodebuild", MACOS_CI)

    def test_required_check_name_stays_stable_and_honors_failure(self):
        self.assertIn("required-check:", MACOS_CI)
        self.assertIn("name: Build & Test (Apple Silicon arm64)", MACOS_CI)
        self.assertIn("needs: governed", MACOS_CI)
        self.assertIn("if: always() && github.event_name == 'pull_request'", MACOS_CI)
        self.assertIn('if [[ "$GOVERNED_RESULT" != "success" ]]; then', MACOS_CI)
        self.assertIn("DRAFT_DEFERRED / PRODUCT_TESTS_NOT_RUN", MACOS_CI)

    def test_manual_plan_only_cannot_masquerade_as_required_check(self):
        self.assertIn("default: none", MACOS_CI)
        self.assertIn("options: [focused, milestone, ready, release, none]", MACOS_CI)
        self.assertIn("github.event_name == 'pull_request'", MACOS_CI)
        self.assertIn("comparison_base:", MACOS_CI)

    def test_qa_dmg_is_manual_only(self):
        header = QA_DMG.split("jobs:", 1)[0]
        self.assertIn("  workflow_dispatch:", header)
        self.assertNotIn("  pull_request:", header)
        self.assertIn("name: QA DMG", header)
        self.assertIn("tools/release/build_dmg.sh", QA_DMG)

    def test_benchmark_pr_not_duplicated_but_manual_main_retained(self):
        header = BENCHMARK.split("jobs:", 1)[0]
        self.assertNotIn("  pull_request:", header)
        self.assertIn("  push:", header)
        self.assertIn("  workflow_dispatch:", header)
        self.assertIn("tools/benchmark/**", header)

    def test_catalog_has_matching_benchmark_lane(self):
        by_id = {entry["id"]: entry for entry in CAPABILITIES["tests"]}
        self.assertIn("benchmark-selftest", by_id)
        self.assertIn("tools/benchmark/**", by_id["benchmark-selftest"]["paths"])
        self.assertTrue(by_id["benchmark-selftest"]["fork_safe"])


if __name__ == "__main__":
    unittest.main()
