# FloatTabs Current Status

**Verified date:** 2026-11-05  
**Repository:** Lost0rz/FloatTabs  
**Effective main control mode:** FILE_CONTROL (not yet switched)  
**Task:** FT-GOV-ISSUE-CONTROL-MIGRATION-001  
**Stage:** PRE_CUTOVER_PREPARATION / CUTOVER_READY=NO  
**Migration branch:** `codex/ft-issue-control-migration-001`  
**Main observed:** `d64c9ec62660e9a855056c08e013a71a58db821b`  
**Release:** None authorized.

## New Issue collaboration system — preparation

The user requested on 2026-11-05 that FloatTabs adopt Engineering Governance's GitHub Issue-based Web ChatGPT ↔ local Codex Desktop handoff, with GitHub CLI as local synchronization.

- Migration preparation Issue: **#197** — https://github.com/Lost0rz/FloatTabs/issues/197.
- Carry-forward active product task: **#198** — https://github.com/Lost0rz/FloatTabs/issues/198, task ID `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`.
- Both are **UNAPPROVED / NON-EXECUTABLE** until exact `SPEC_APPROVAL_V1` by an authenticated project approver is verified.
- `LOCAL_GH_READ_WRITE_PREFLIGHT=UNVERIFIED`: a successful Web GitHub connector operation does not establish the Mac's local `gh` capability.
- `SPEC_REVISION_DIGEST_APPROVAL=UNVERIFIED`.
- `LOCAL_WRITER_UNIQUE_WORK=UNKNOWN_FROM_WEB`: do not reset or clean worktrees.
- `ISSUE_CONTROL_EFFECTIVE=NO`; until the migration PR is verified merged, `CURRENT_TASK.md` remains the current authorization on main.
- Keep the migration PR Draft until CLI, approvals, task handoff, exact diff and host merge gates are proven. Do not delete legacy controls in preparation or claim cutover.

## Existing product task isolation

- **PR #196**: MERGED/CLOSED, merge commit `d64c9ec62660e9a855056c08e013a71a58db821b`, human accepted Panel/Focus correction. No release authorized by that closeout.
- **PR #195**: OPEN/DRAFT/UNMERGED, branch `codex/adaptive-lifecycle-wp2-policy`, observed remote branch commit `a9f07ca02df10d2ea3d0292d1afa5669d115da42`. Preserve branch and all unique worktrees.
- The #195 **branch control files**, rather than its older PR description, report the in-flight ChatGPT hibernated-runtime URL restore corrective. Focused tests, exact-head split XCTest, macOS arm64 CI and QA DMG passed on the recorded implementation gate. `HUMAN_UI_ACCEPTANCE=PENDING`, `PR_195_MERGE_READY=NO`.
- The issue migration does not authorize merging #195, beginning WP3/WP4, modifying its branch/worktree, or changing Browser Profile/session/site data.

## Cutover acceptance

Require actual local `gh` issue JSON read/write with verified comment ID, official 19-field spec digest+approval verification for both still-executable issues, a trusted `ISSUE_APPROVERS` policy, one safe migration PR with `AGENTS.md: ISSUE_CONTROL` and root Task/Status retired simultaneously, no loss/reintroduction of #195 work, and verified merged commit on main. Until then, **FILE_CONTROL stays authoritative**.

Current migration authorization and STOP conditions: `CURRENT_TASK.md` on this preparation branch and the installed Engineering Governance project-governance migration contract.
