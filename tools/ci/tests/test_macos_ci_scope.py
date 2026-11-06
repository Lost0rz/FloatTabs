import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import classify_macos_ci_scope as scope_classifier
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

    def test_pull_request_rename_classifies_both_current_and_previous_paths(self):
        with patch.object(
            scope_classifier,
            "_api_json",
            return_value=[
                {
                    "filename": "docs/OldWebView.md",
                    "previous_filename": "FloatTabs/Web/OldWebView.swift",
                    "status": "renamed",
                }
            ],
        ):
            paths, incomplete = scope_classifier._pull_request_paths(201)

        self.assertFalse(incomplete)
        self.assertEqual(
            paths,
            ["docs/OldWebView.md", "FloatTabs/Web/OldWebView.swift"],
        )
        self.assertTrue(classify_paths(paths)["run_product_tests"])

    def test_compare_rename_classifies_both_current_and_previous_paths(self):
        with patch.object(
            scope_classifier,
            "_api_json",
            return_value={
                "status": "ahead",
                "files": [
                    {
                        "filename": "docs/OldTests.md",
                        "previous_filename": "FloatTabsTests/OldTests.swift",
                        "status": "renamed",
                    }
                ],
            },
        ):
            paths, incomplete = scope_classifier._push_paths("a" * 40, "b" * 40)

        self.assertFalse(incomplete)
        self.assertEqual(
            paths,
            ["docs/OldTests.md", "FloatTabsTests/OldTests.swift"],
        )
        self.assertTrue(classify_paths(paths)["run_product_tests"])

    def test_compare_missing_or_invalid_file_manifest_fails_safe(self):
        invalid_results = (
            {"status": "ahead"},
            {"status": "ahead", "files": None},
            {"status": "ahead", "files": "not-a-list"},
            {"status": "ahead", "files": []},
            {"status": "ahead", "files": [None]},
            {"status": "ahead", "files": [{"filename": ""}]},
            {"status": "ahead", "files": [{"filename": "docs/new.md", "previous_filename": None}]},
            {"status": "unknown", "files": [{"filename": "docs/new.md"}]},
        )
        for result in invalid_results:
            with self.subTest(result=result), patch.object(
                scope_classifier, "_api_json", return_value=result
            ):
                paths, incomplete = scope_classifier._push_paths("a" * 40, "b" * 40)
                self.assertTrue(incomplete)
                self.assertEqual(paths, [])

    def test_missing_compare_manifest_emits_full_fail_safe_outputs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            event_path = Path(temp_dir) / "event.json"
            output_path = Path(temp_dir) / "github-output.txt"
            event_path.write_text(
                json.dumps({"before": "a" * 40, "after": "b" * 40}),
                encoding="utf-8",
            )
            environment = {
                "GITHUB_EVENT_NAME": "push",
                "GITHUB_EVENT_PATH": str(event_path),
                "GITHUB_OUTPUT": str(output_path),
            }
            captured = io.StringIO()
            with patch.dict(os.environ, environment), patch.object(
                scope_classifier, "_api_json", return_value={"status": "ahead"}
            ), redirect_stdout(captured):
                self.assertEqual(scope_classifier.main(), 0)

            decision = json.loads(captured.getvalue())
            outputs = output_path.read_text(encoding="utf-8")

        self.assertTrue(decision["run_product_tests"])
        self.assertTrue(decision["run_workflow_validation"])
        self.assertEqual(decision["scope"], "fail-safe-full")
        self.assertFalse(decision["workflow_files_available"])
        self.assertIn("run_product_tests=true", outputs)

    def test_workflow_change_runs_configuration_validation_only(self):
        result = classify_paths([".github/workflows/macos-ci.yml"])
        self.assertFalse(result["run_product_tests"])
        self.assertTrue(result["run_workflow_validation"])
        self.assertEqual(result["scope"], "workflow-config")
        self.assertEqual(result["workflow_files"], [".github/workflows/macos-ci.yml"])

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
