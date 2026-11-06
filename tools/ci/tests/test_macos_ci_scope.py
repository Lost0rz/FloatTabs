import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from classify_macos_ci_scope import classify_paths, event_decision


class MacOSCIScopeTests(unittest.TestCase):
    def test_task_and_status_controls_skip_product_tests(self):
        result = classify_paths(["CURRENT_TASK.md", "CURRENT_STATUS.md"])
        self.assertFalse(result["run_product_tests"])
        self.assertFalse(result["run_workflow_validation"])
        self.assertEqual(result["scope"], "control-only")

    def test_agents_policy_file_skips_product_tests(self):
        result = classify_paths(["AGENTS.md"])
        self.assertFalse(result["run_product_tests"])

    def test_ordinary_documentation_skips_product_tests(self):
        result = classify_paths(["docs/architecture/README.md", "README.md"])
        self.assertFalse(result["run_product_tests"])
        self.assertFalse(result["run_workflow_validation"])

    def test_swift_product_source_runs_product_tests(self):
        result = classify_paths(["FloatTabs/Web/WebViewPool.swift"])
        self.assertTrue(result["run_product_tests"])

    def test_xctest_change_runs_product_tests(self):
        result = classify_paths(["FloatTabsTests/WebViewPoolTests.swift"])
        self.assertTrue(result["run_product_tests"])

    def test_workflow_change_runs_configuration_validation_only(self):
        result = classify_paths([".github/workflows/macos-ci.yml"])
        self.assertFalse(result["run_product_tests"])
        self.assertTrue(result["run_workflow_validation"])
        self.assertEqual(result["scope"], "workflow-config")

    def test_actionlint_configuration_runs_configuration_validation_only(self):
        result = classify_paths([".github/actionlint.yaml"])
        self.assertFalse(result["run_product_tests"])
        self.assertTrue(result["run_workflow_validation"])

    def test_manual_dispatch_always_runs_full_product_tests(self):
        result = event_decision("workflow_dispatch", [])
        self.assertTrue(result["run_product_tests"])
        self.assertEqual(result["scope"], "manual-full")

    def test_unknown_path_fails_safe_to_product_tests(self):
        result = classify_paths(["new-root-config.toml"])
        self.assertTrue(result["run_product_tests"])
        self.assertEqual(result["reason"], "unclassified-path-fail-safe")

    def test_mixed_control_and_product_paths_run_product_tests(self):
        result = classify_paths(["CURRENT_STATUS.md", "FloatTabs/App/AppDelegate.swift"])
        self.assertTrue(result["run_product_tests"])

    def test_mixed_workflow_and_product_paths_run_both_validations(self):
        result = classify_paths([".github/workflows/qa-dmg.yml", "FloatTabs/App/AppDelegate.swift"])
        self.assertTrue(result["run_product_tests"])
        self.assertTrue(result["run_workflow_validation"])


if __name__ == "__main__":
    unittest.main()
