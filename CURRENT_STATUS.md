# FloatTabs Current Status

Verified date: 2026-11-06
Repository: Lost0rz/FloatTabs
Control mode: FILE_CONTROL
Current authorized task: FT-CI-TRIGGER-BOUNDARY-001
Current stage: DRAFT PR OPEN / VALIDATION PASS / WAITING FOR INDEPENDENT WEB AUDIT
Branch: codex/ft-ci-trigger-boundary-001
Base main: d64c9ec62660e9a855056c08e013a71a58db821b
PR: #201 — OPEN / DRAFT; validated workflow implementation head `b2331024eab3735fee44b156301c45c05947c66f`
Release: NOT_AUTHORIZED

## Task authority and handoff

The user authorized this independent CI corrective and the bounded workflow-ownership transfer on 2026-11-06. This branch alone carries the new FILE_CONTROL Task and Status. The task does not use Issue #197 or PR #199 as authorization and does not modify PR #195, #199 or #200 branches/worktrees.

PR #195 retains all product source, product tests, its XCTest partition strategy, and local unique work. Its committed CI trigger/scheduling and QA DMG trigger behavior are transferred to this task for correction. The old branch and worktree remain preserved and read-only for the transferred workflow scope.

## Verified repository state

- main remains FILE_CONTROL at d64c9ec62660e9a855056c08e013a71a58db821b. Its control snapshot still describes merged PR #196 and is reconciled by this task branch only.
- PR #195 is OPEN / DRAFT / CONFLICTING at a9f07ca02df10d2ea3d0292d1afa5669d115da42. Its local worktree is at d02b1a24718fe7aaa569dd7c49713bba4c39c1ac, seven commits behind the remote, with local unique changes preserved:
  - modified FloatTabs.xcodeproj/project.pbxproj
  - modified FloatTabsTests/WebFocusAdapterTests.swift
  - modified FloatTabsTests/WebViewFactoryTests.swift
  - modified FloatTabsTests/WebsiteLayoutGeometryRegressionTests.swift
  - untracked FloatTabsTests/WebKitFixtureTeardown.swift
- PR #199 is OPEN / DRAFT at b69c86c551fc5c7d3bb400c3bd2243678b1b5aae. It remains a separate migration proposal; it does not change main's FILE_CONTROL authority.
- PR #200 is OPEN / DRAFT / MERGEABLE at fa518dbc2c11528bd34bbb9019d64c8f454136fa, with human two-display acceptance still pending.
- Branch protection requires the strict GitHub Actions context Build & Test (Apple Silicon arm64), app ID 15368. No protection rule change is authorized.

## CI evidence and boundaries

- PR #199 received nine macOS CI runs. Each ran Debug, Release, native arm64 verification, and XCTest; each failed during XCTest. Preserve the WebKit failure evidence separately.
- PR #200 received repeated QA DMG pull_request builds on successive heads, in addition to manual dispatch runs.
- The current self-hosted product job uses [self-hosted, macOS, ARM64, mac-mini-ci]. Keep product code off that runner for fork PRs.
- Workflow configuration validation may use a GitHub-hosted runner. A skipped product test must be reported as skipped, never as PRODUCT_TESTS_PASS.

## Focused verification

- actionlint v1.7.12 passed against both workflows; the official Darwin and Linux release archive checksums were verified, including the Linux digest pinned by the workflow.
- 16 classifier and workflow-contract tests passed, covering control/status, AGENTS, ordinary documentation, Swift source, XCTest, workflow configuration, manual full dispatch, unknown paths, mixed paths, required-check entrypoint, runner boundary, QA DMG draft behavior, and the scoped actionlint file list.
- Python syntax compilation and `git diff --check` passed.
- Required context and strict protection were re-read live; the required job name remains `Build & Test (Apple Silicon arm64)`.
- PR-open macOS CI run `42134839759`: Scope Gate passed with `workflow-config`; product tests were skipped. Workflow validation failed because actionlint included the unrelated existing `publish-release.yml` shellcheck warning (`SC2129`). The required aggregator reported config failure; QA DMG run `42134839703` skipped its build job for this Draft PR. No Apple Silicon runner or product XCTest was used.
- Corrective PR-synchronize macOS CI run `42135136999` at implementation commit `b2331024eab3735fee44b156301c45c05947c66f`: `workflow-config` Scope Gate, actionlint on the two owned workflow files, 16 helper/contract tests, and required aggregator all passed. Product Build & Test was skipped; no Apple Silicon runner or XCTest was used.
- Manual full dispatch remains available. No product XCTest has been run locally.

## Current execution

No product source or XCTest assertion changes are in scope. No existing PR/worktree is being edited. The independent worktree was created at the exact current main base and contains only this task's control, workflow, and CI classifier changes. The initial implementation is commit `5547c2b`; one bounded actionlint-scope correction is commit `b233102`. A final control-only receipt update will record the live PR and validation outcome; it must not trigger product tests.
