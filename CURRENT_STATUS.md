# FloatTabs Current Status

**Verified date:** 2026-11-05  
**Repository:** Lost0rz/FloatTabs  
**Effective main control mode:** FILE_CONTROL (not yet switched)  
**Task:** FT-GOV-ISSUE-CONTROL-MIGRATION-001  
**Stage:** WP01_COMPLETE / REMOTE_GOVERNANCE_ROUTING_CORRECTIVE / CUTOVER_READY=NO  
**Migration branch:** `codex/ft-issue-control-migration-001`  
**Migration PR:** [#199](https://github.com/Lost0rz/FloatTabs/pull/199) — OPEN/DRAFT/UNMERGED  
**Main observed:** `d64c9ec62660e9a855056c08e013a71a58db821b`  
**Release:** None authorized.

## New Issue collaboration system — preparation

The user requested on 2026-11-05 that FloatTabs adopt Engineering Governance's GitHub Issue-based Web ChatGPT ↔ local Codex Desktop handoff, with GitHub CLI as local synchronization.

- Migration preparation Issue: **#197** — https://github.com/Lost0rz/FloatTabs/issues/197.
- Carry-forward active product task: **#198** — https://github.com/Lost0rz/FloatTabs/issues/198, task ID `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`.
- Both are **UNAPPROVED / NON-EXECUTABLE** until exact `SPEC_APPROVAL_V1` by an authenticated project approver is verified.
- `LOCAL_GH_READ_WRITE_PREFLIGHT=PASS`: local Codex verified authenticated `gh` Issue read/write and a real GitHub test comment [#6659119976](https://github.com/Lost0rz/FloatTabs/issues/197#issuecomment-6659119976).
- `OFFICIAL_SPEC_DIGEST=STRUCTURE_PASS_APPROVAL_PENDING`: #197 revision 1 `48e547e9...636d44c8c`, #198 revision 1 `41458ae8...f14547bd2`; both **lack** separate trusted approval comments.
- `LOCAL_WRITER_UNIQUE_WORK=UNVERIFIED`: Codex identified a PR #195 worktree at `d02b1a24`, seven commits behind remote with four modified tracked files and one untracked test fixture. Writer/unique-work disposition remains unverified; do not reset, clean, stash, force-move or overwrite the checkout.
- `ISSUE_CONTROL_EFFECTIVE=NO`; until the migration PR is verified merged, `CURRENT_TASK.md` remains the current authorization on main.
- Keep the migration PR Draft until CLI, approvals, task handoff, exact diff and host merge gates are proven. Do not delete legacy controls in preparation or claim cutover.

## Existing product task isolation

- **PR #196**: MERGED/CLOSED, merge commit `d64c9ec62660e9a855056c08e013a71a58db821b`, human accepted Panel/Focus correction. No release authorized by that closeout.
- **PR #195**: OPEN/DRAFT/UNMERGED, branch `codex/adaptive-lifecycle-wp2-policy`, observed remote branch commit `a9f07ca02df10d2ea3d0292d1afa5669d115da42`. Preserve branch and all unique worktrees.
- The #195 **branch control files**, rather than its older PR description, report the in-flight ChatGPT hibernated-runtime URL restore corrective. Focused tests, exact-head split XCTest, macOS arm64 CI and QA DMG passed on the recorded implementation gate. `HUMAN_UI_ACCEPTANCE=PENDING`, `PR_195_MERGE_READY=NO`.
- The issue migration does not authorize merging #195, beginning WP3/WP4, modifying its branch/worktree, or changing Browser Profile/session/site data.

## Cutover acceptance

Local `gh` read/write and official structural digests now pass. The preparation branch documents `ISSUE_APPROVERS: Lost0rz`, a proposed trusted-actor policy that becomes authoritative only when accepted on main. Still require independent authenticated human approval for both exact Issue specs, scope/writer/unique-work isolation of #195, the **subsequent atomic** migration PR change to `AGENTS.md: ISSUE_CONTROL` with root Task/Status retired together, relevant host checks and verified merge on main. Until then, **FILE_CONTROL stays authoritative**.

Current migration authorization and STOP conditions: `CURRENT_TASK.md` on this preparation branch and the installed Engineering Governance project-governance migration contract.
