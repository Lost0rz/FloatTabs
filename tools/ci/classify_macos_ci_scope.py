#!/usr/bin/env python3
"""Classify GitHub changes for the FloatTabs macOS CI boundary."""

from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import PurePosixPath
from typing import Any


PRODUCT_PREFIXES = (
    "FloatTabs/",
    "FloatTabsTests/",
    "FloatTabs.xcodeproj/",
    "tools/release/",
)
PRODUCT_FILES = {
    "Package.swift",
    "Package.resolved",
}
CONFIG_PREFIXES = (
    ".github/workflows/",
    ".github/actions/",
    "tools/ci/",
)
CONFIG_FILES = {
    ".github/ci-capabilities.json",
    ".github/actionlint.yaml",
    ".github/actionlint.yml",
}
CONTROL_FILES = {
    "AGENTS.md",
    "CURRENT_TASK.md",
    "CURRENT_STATUS.md",
    "README",
    "README.md",
    "CHANGELOG",
    "CHANGELOG.md",
    "CONTRIBUTING",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "LICENSE",
    "LICENSE.md",
    "NOTICE",
}
CONTROL_SUFFIXES = (".md", ".mdx", ".rst")
MAX_COMPARE_FILES = 300
MAX_PULL_REQUEST_FILES = 3000
VALID_COMPARE_STATUSES = {"ahead", "behind", "identical", "diverged"}


def _file_paths(files: Any) -> list[str] | None:
    """Validate a GitHub changed-file manifest and include both rename paths."""
    if not isinstance(files, list):
        return None

    paths: list[str] = []
    for item in files:
        if not isinstance(item, dict):
            return None
        filename = item.get("filename")
        if not isinstance(filename, str) or not filename.strip():
            return None
        paths.append(filename)

        if "previous_filename" in item:
            previous_filename = item["previous_filename"]
            if not isinstance(previous_filename, str) or not previous_filename.strip():
                return None
            paths.append(previous_filename)

    return paths


def _workflow_file_candidates(paths: list[str]) -> list[str]:
    """Select workflow YAML paths from a changed-file list for scoped actionlint."""
    candidates = set()
    for raw_path in paths:
        path = raw_path.replace("\\", "/")
        while path.startswith("./"):
            path = path[2:]
        parts = PurePosixPath(path).parts
        if (
            len(parts) >= 3
            and parts[:2] == (".github", "workflows")
            and ".." not in parts
            and PurePosixPath(path).suffix.lower() in {".yml", ".yaml"}
        ):
            candidates.add(path)
    return sorted(candidates)


def classify_paths(paths: list[str]) -> dict[str, Any]:
    """Return whether paths need product tests and/or workflow validation."""
    run_product_tests = False
    run_workflow_validation = False
    saw_control_path = False
    saw_unknown_path = False

    for raw_path in paths:
        path = raw_path.replace("\\", "/")
        while path.startswith("./"):
            path = path[2:]
        if any(path.startswith(prefix) for prefix in PRODUCT_PREFIXES) or path in PRODUCT_FILES:
            run_product_tests = True
        elif path in CONFIG_FILES or any(path.startswith(prefix) for prefix in CONFIG_PREFIXES):
            run_workflow_validation = True
        elif (
            path.startswith("docs/")
            or path.startswith(".github/ISSUE_TEMPLATE/")
            or path.startswith(".github/PULL_REQUEST_TEMPLATE")
            or path in CONTROL_FILES
            or PurePosixPath(path).suffix.lower() in CONTROL_SUFFIXES
        ):
            saw_control_path = True
        else:
            # Unclassified files fail safe to product verification.
            run_product_tests = True
            saw_unknown_path = True

    if run_product_tests:
        scope = "product"
    elif run_workflow_validation:
        scope = "workflow-config"
    else:
        scope = "control-only"

    if not paths:
        reason = "no-changed-files"
    elif saw_unknown_path:
        reason = "unclassified-path-fail-safe"
    elif run_product_tests and run_workflow_validation:
        reason = "product-and-workflow-config"
    elif run_product_tests:
        reason = "product-path"
    elif run_workflow_validation:
        reason = "workflow-config-path"
    elif saw_control_path:
        reason = "control-or-documentation-only"
    else:
        reason = "no-product-path"

    return {
        "run_product_tests": run_product_tests,
        "run_workflow_validation": run_workflow_validation,
        "scope": scope,
        "reason": reason,
        "workflow_files": _workflow_file_candidates(paths),
        "workflow_files_available": True,
    }


def event_decision(event_name: str, paths: list[str]) -> dict[str, Any]:
    """Apply event-level policy after changed paths have been collected."""
    if event_name == "workflow_dispatch":
        return {
            "run_product_tests": True,
            "run_workflow_validation": False,
            "scope": "manual-full",
            "reason": "manual-full-verification",
            "workflow_files": [],
            "workflow_files_available": True,
        }
    return classify_paths(paths)


def _api_json(path: str) -> Any:
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    token = os.environ.get("GH_TOKEN", "")
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    if not repository or not token:
        raise RuntimeError("GitHub API context is unavailable")

    request = urllib.request.Request(
        f"{api_url}/repos/{repository}/{path.lstrip('/')}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "FloatTabs-CI-Scope-Gate",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def _pull_request_paths(number: int) -> tuple[list[str], bool]:
    paths: list[str] = []
    page = 1
    while page <= MAX_PULL_REQUEST_FILES // 100:
        query = urllib.parse.urlencode({"per_page": 100, "page": page})
        files = _api_json(f"pulls/{number}/files?{query}")
        batch_paths = _file_paths(files)
        if batch_paths is None:
            return paths, True
        paths.extend(batch_paths)
        if len(files) < 100:
            return paths, False
        page += 1

    # The files API is capped at 3,000 entries. Treat the cap as unknown scope.
    return paths, True


def _push_paths(before: str, after: str) -> tuple[list[str], bool]:
    if not before or not after or set(before) == {"0"}:
        return [], True
    comparison = urllib.parse.quote(f"{before}...{after}", safe=".")
    query = urllib.parse.urlencode({"per_page": 100})
    result = _api_json(f"compare/{comparison}?{query}")
    status = result.get("status") if isinstance(result, dict) else None
    if not isinstance(status, str) or status not in VALID_COMPARE_STATUSES:
        return [], True
    files = result.get("files")
    paths = _file_paths(files)
    if paths is None or not files:
        return [], True
    # GitHub's compare response caps changed files at 300; fail safe at the cap.
    return paths, len(files) >= MAX_COMPARE_FILES


def changed_paths(event: dict[str, Any], event_name: str) -> tuple[list[str], bool]:
    if event_name == "pull_request":
        number = int(event["pull_request"]["number"])
        return _pull_request_paths(number)
    if event_name == "push":
        return _push_paths(event.get("before", ""), event.get("after", ""))
    raise RuntimeError(f"Unsupported event for scope classification: {event_name}")


def _write_outputs(decision: dict[str, Any]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    lines = [
        f"run_product_tests={str(decision['run_product_tests']).lower()}",
        f"run_workflow_validation={str(decision['run_workflow_validation']).lower()}",
        f"scope={decision['scope']}",
        "workflow_files=" + json.dumps(decision.get("workflow_files", []), separators=(",", ":")),
        "workflow_files_available=" + str(decision.get("workflow_files_available", True)).lower(),
    ]
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write("\n".join(lines) + "\n")
    print(json.dumps({**decision, "outputs": lines}, sort_keys=True))


def main() -> int:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    if event_name == "workflow_dispatch":
        decision = event_decision(event_name, [])
        _write_outputs(decision)
        return 0

    try:
        with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as event_file:
            event = json.load(event_file)
        paths, truncated = changed_paths(event, event_name)
        if truncated:
            decision = {
                "run_product_tests": True,
                "run_workflow_validation": True,
                "scope": "fail-safe-full",
                "reason": "change-list-unavailable-or-truncated",
                "workflow_files": [],
                "workflow_files_available": False,
            }
        else:
            decision = event_decision(event_name, paths)
    except Exception as error:
        # API/context errors must never silently skip product validation.
        decision = {
            "run_product_tests": True,
            "run_workflow_validation": True,
            "scope": "fail-safe-full",
            "reason": f"scope-api-fallback-{type(error).__name__}",
            "workflow_files": [],
            "workflow_files_available": False,
        }

    _write_outputs(decision)
    return 0


if __name__ == "__main__":
    sys.exit(main())
