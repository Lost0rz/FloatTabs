import json
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MACOS_CI = (REPOSITORY_ROOT / ".github/workflows/macos-ci.yml").read_text(encoding="utf-8")
QA_DMG = (REPOSITORY_ROOT / ".github/workflows/qa-dmg.yml").read_text(encoding="utf-8")
BENCHMARK = (REPOSITORY_ROOT / ".github/workflows/benchmark-tool-ci.yml").read_text(encoding="utf-8")
CAPABILITIES = json.loads((REPOSITORY_ROOT / ".github/ci-capabilities.json").read_text(encoding="utf-8"))


class GovernedCIWorkflowContractTests(unittest.TestCase):
    def test_pr_manual_and_scoped_main_push_triggers(self):
        header = MACOS_CI.split("jobs:", 1)[0]
        self.assertIn("  pull_request:", header)
        self.assertIn("  workflow_dispatch:", header)
        self.assertIn("  push:", header)
        self.assertIn("    branches: [main]", header)
        self.assertNotIn("    paths:", header)
        self.assertIn("Main push affected Domain plan", MACOS_CI)
        self.assertIn("Main push scoped test", MACOS_CI)
        self.assertIn("Main push scoped verification", MACOS_CI)

    def test_shared_router_is_pinned_and_only_accepted_catalog_is_used(self):
        self.assertIn("uses: Lost0rz/Engineering-Governance/.github/workflows/ci-router-reusable.yml@v0.10.1", MACOS_CI)
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

    def test_benchmark_pr_and_main_are_routed_without_duplicate_push(self):
        header = BENCHMARK.split("jobs:", 1)[0]
        self.assertNotIn("  pull_request:", header)
        self.assertNotIn("  push:", header)
        self.assertIn("  workflow_dispatch:", header)
        self.assertIn("tools/benchmark/**", json.dumps(CAPABILITIES))

    def test_catalog_has_matching_benchmark_lane(self):
        by_id = {entry["id"]: entry for entry in CAPABILITIES["tests"]}
        self.assertIn("benchmark-selftest", by_id)
        self.assertIn("tools/benchmark/**", by_id["benchmark-selftest"]["paths"])
        self.assertTrue(by_id["benchmark-selftest"]["fork_safe"])


    def test_push_job_does_not_invoke_full_xctest_or_skip_unmapped_changes(self):
        self.assertIn("if: github.event_name == 'push'", MACOS_CI)
        self.assertIn("stage milestone", MACOS_CI)
        self.assertIn("git -C project merge-base --is-ancestor", MACOS_CI)
        self.assertIn("MAIN_PUSH_SCOPE_UNVERIFIED", MACOS_CI)
        self.assertIn("MAIN_PUSH_SCOPED_TESTS_PASS", MACOS_CI)
        self.assertNotIn("xcodebuild", MACOS_CI)
        self.assertIn("if: always() && github.event_name == 'pull_request'", MACOS_CI)

    def test_release_shell_has_valid_syntax_without_building_dmg(self):
        import subprocess

        script = REPOSITORY_ROOT / "tools/release/build_dmg.sh"
        check = subprocess.run(["bash", "-n", str(script)],
                               capture_output=True, text=True, check=False)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertIn("tools/release/**",
                      next(t["paths"] for t in CAPABILITIES["tests"]
                           if t["id"] == "ci-contracts"))

    def test_catalog_has_resource_and_build_separation(self):
        lanes = {entry["id"]: entry for entry in CAPABILITIES["tests"]}
        self.assertTrue(lanes["app-resources"]["fork_safe"])
        self.assertEqual(lanes["app-resources"]["runner"], ["ubuntu-latest"])
        self.assertNotIn("test", lanes["swift-build"]["command"])
        self.assertIn("test", lanes["swift-integration"]["command"])
        self.assertNotIn("FloatTabs.xcodeproj/project.pbxproj",
                         lanes["swift-integration"]["paths"])


if __name__ == "__main__":
    unittest.main()
