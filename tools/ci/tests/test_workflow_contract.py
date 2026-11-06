import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MACOS_CI = (REPOSITORY_ROOT / ".github/workflows/macos-ci.yml").read_text(encoding="utf-8")
QA_DMG = (REPOSITORY_ROOT / ".github/workflows/qa-dmg.yml").read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_macOS_trigger_keeps_required_check_entrypoint_for_all_paths(self):
        triggers = MACOS_CI.split("jobs:", 1)[0]
        self.assertIn("  push:", triggers)
        self.assertIn("  pull_request:", triggers)
        self.assertIn("  workflow_dispatch:", triggers)
        self.assertNotIn("    paths:", triggers)

    def test_required_check_name_and_aggregator_are_stable(self):
        self.assertRegex(
            MACOS_CI,
            re.compile(
                r"required-check:\n\s+name: Build & Test \(Apple Silicon arm64\)\n"
                r"\s+needs: \[scope-gate, workflow-validation, product-tests\]\n"
                r"\s+if: always\(\)",
            ),
        )
        for status in (
            "SCOPE_GATE_PASS / PRODUCT_TESTS_SKIPPED",
            "PRODUCT_TESTS_PASS",
            "PRODUCT_TESTS_FAIL",
        ):
            self.assertIn(status, MACOS_CI)

    def test_product_tests_keep_runner_boundary_and_cancel_stale_runs(self):
        self.assertIn("cancel-in-progress: true", MACOS_CI)
        self.assertIn("runs-on: [self-hosted, macOS, ARM64, mac-mini-ci]", MACOS_CI)
        self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", MACOS_CI)

    def test_configuration_validation_is_limited_to_the_owned_workflows(self):
        self.assertIn(
            '"$RUNNER_TEMP/actionlint" .github/workflows/macos-ci.yml .github/workflows/qa-dmg.yml',
            MACOS_CI,
        )

    def test_qa_dmg_is_manual_or_review_boundary_and_skips_draft_build(self):
        self.assertIn("  workflow_dispatch:", QA_DMG)
        self.assertRegex(QA_DMG, re.compile(r"types:\n\s+- opened\n\s+- ready_for_review"))
        self.assertIn("github.event.pull_request.draft == false", QA_DMG)
        self.assertIn("    paths:", QA_DMG)


if __name__ == "__main__":
    unittest.main()
