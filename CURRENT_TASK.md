# FloatTabs Current Task

**TASK_ID:** FT-CI-TRIGGER-BOUNDARY-001
**TASK_CLASS:** CORRECTIVE
**STATE:** TARGETED_VALIDATION_FOLLOW_UP
**CONTROL_MODE:** FILE_CONTROL
**BRANCH:** `codex/ft-ci-trigger-boundary-001`
**BASE:** `main` at `d64c9ec62660e9a855056c08e013a71a58db821b`
**PR:** #201 — open Draft PR for independent audit

## Authorization

On 2026-11-06, the user explicitly authorized this independent CI corrective and a bounded transfer of workflow trigger/scheduling ownership from PR #195. This task is authorized by that direct instruction; it does not rely on Issue #197 or PR #199 as authorization.

PR #195 retains product source, product tests, its XCTest partition strategy, and all local unique work. This task owns only the CI trigger/scheduling policy in `.github/workflows/macos-ci.yml` and `.github/workflows/qa-dmg.yml`, including scope classification, control-only detection, concurrency, QA DMG trigger boundaries, and Required Checks compatibility. Its old branch/worktree is preserved read-only for the transferred workflow scope. Do not modify or close PR #195, #199, or #200, or their branches/worktrees.

## Objective and allowed changes

Prevent control-plane and ordinary documentation-only changes from running the full macOS product build and XCTest suite, while retaining required product verification for product and test changes. Keep the required check context `Build & Test (Apple Silicon arm64)` compatible with current branch protection.

Allowed changes are limited to:

- `.github/workflows/macos-ci.yml` trigger, scope-gate, job condition, concurrency, and required-check aggregation behavior;
- `.github/workflows/qa-dmg.yml` PR trigger conditions for QA DMG scheduling;
- narrowly scoped CI classifier/configuration validation helper(s) and tests, if needed;
- this task's `CURRENT_TASK.md` and `CURRENT_STATUS.md` controls.

Do not change product source, XCTest assertions, PR #195's test partition strategy, runner inventory/security boundary, branch protection, release behavior, or unrelated project controls. Do not wholesale replace PR #195's workflow work; retain its valid product/test portions conceptually and document the later integration sequence.

## Required behavior

1. Ordinary governance/control documents, Issue templates, and ordinary docs do not execute product Build & Test or XCTest.
2. Product source, tests, Xcode project, and relevant build/release tooling changes run required product verification. Mixed or unclassified changes fail safe to product verification.
3. Workflow/configuration changes receive appropriate static workflow validation without unconditionally running product XCTest.
4. `workflow_dispatch` retains a full product verification path.
5. Same-PR obsolete runs are canceled when a newer run supersedes them.
6. Keep product execution on `[self-hosted, macOS, ARM64, mac-mini-ci]`; never execute untrusted fork PR code on the self-hosted runner.
7. Always report the required context `Build & Test (Apple Silicon arm64)` so path classification cannot leave branch protection Pending. Distinguish `SCOPE_GATE_PASS / PRODUCT_TESTS_SKIPPED`, `PRODUCT_TESTS_PASS`, and `PRODUCT_TESTS_FAIL`; a skipped product job is not a product pass.
8. QA DMG PR builds are limited to eligible product changes and the selected review boundary; manual dispatch remains available.
9. Preserve real test failure diagnostics and reporting.

## Verification and delivery

Focused local checks passed on 2026-11-06, including actionlint v1.7.12, Python syntax compilation, and the scope/contract test matrix. The first real PR-open run passed scope classification and correctly skipped product tests, but exposed that actionlint scanned an unrelated existing workflow warning. The bounded follow-up now validates only the two workflows owned by this task. Required-check name and branch protection were read live. Do not run the product XCTest suite locally or dispatch unnecessary full tests; perform only the necessary correction run and final delivery-state verification, and report every actual Actions run and scope.

Create one independent branch and one Draft PR, leave it unmerged, attach the PR to this task, and stop after exact-head delivery verification. Do not mark Ready, merge, release, or start another full-test loop. Keep prior WebKit test failure evidence separate from this governance/CI correction.

## Stop conditions

Stop affected writes and report if FILE_CONTROL ownership, Required Checks compatibility, same-repository fork safety, a concurrent writer on the transferred workflow scope, or preservation of PR #195's unique work cannot be verified. Do not force-overwrite, reset, stash, clean, or alter another task's worktree. Do not weaken product test requirements or hide failures to achieve a green status.
