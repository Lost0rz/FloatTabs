# FloatTabs Current Task

**TASK_ID:** FT-GOV-ISSUE-CONTROL-MIGRATION-001  
**TASK_CLASS:** GOVERNANCE / CONTROL-PLANE MIGRATION  
**STATE:** PRE_CUTOVER_PREPARATION / CUTOVER_NOT_AUTHORIZED_YET  
**BASELINE:** `main@d64c9ec62660e9a855056c08e013a71a58db821b` (PR #196 merged)  
**MIGRATION_BRANCH:** `codex/ft-issue-control-migration-001`  
**CONTROL_MODE:** FILE_CONTROL until verified migration PR merge.

## Authorization and objective

On 2026-11-05 the user requested FloatTabs adopt the newly installed Engineering Governance GitHub Issues workflow for Web ChatGPT ↔ local Codex Desktop handoff, with GitHub CLI providing local Issue synchronization. This new task supersedes the already-merged Panel #196 closeout as main's active FILE_CONTROL task. It does **not** authorize product/runtime changes, approval forgery, or merging the separate PR #195.

Prepare one safe, reviewable repository migration from the current three-file FILE_CONTROL to explicit ISSUE_CONTROL, preserving all ongoing tasks and product data. The migration specification is governed by the installed Engineering Governance `project-governance/references/issue-control-migration.md`, `issue-control.md` and `issue-execution-contract.md`.

## Required pre-cutover preparation

1. Confirm main and open PR/Issue state. PR #196 is merged at `d64c9ec6`; PR #195 is OPEN/DRAFT/UNMERGED and must stay untouched. Its own branch `CURRENT_TASK.md` governs the ChatGPT hibernated-runtime URL restore corrective; machine gates passed but human UI acceptance remains pending. Do not replace this current evidence with PR #195's older field-observation summary.
2. Create an explicit migration planning Issue and a carry-forward Issue for `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` using the canonical 19-field `EXECUTION_SPEC_V1`. Initially **unapproved/non-executable**; no agent-generated approval comments.
3. Draft repository changes for ISSUE_CONTROL routing, the trusted `ISSUE_APPROVERS` list, Issue template and documentation routing. Do not change the effective authority on main until verified merge.
4. Verify local `gh` read/write using the selected Issue, capture a real test-comment identifier, and verify the authenticated GitHub actor. **Web connector success does not prove local CLI capability.**
5. Validate the exact spec revision/digest with the installed official helper; obtain matching `SPEC_APPROVAL_V1` comment **posted by the actual authenticated project approver**, not by the executor or a bot impersonating the approver.
6. Reconcile every still-executable task, including #195, and prove no overlap/unique-work harm. Only then prepare the migration PR for review/merge with a single explicit authority transition: `AGENTS.md: ISSUE_CONTROL` and legacy root `CURRENT_TASK.md`/`CURRENT_STATUS.md` retired. The actual cutover happens **only** upon verified merge to main, not when the draft branch or Issues appear.
7. Post-cutover, verify main and the selected Issue approvals. Ensure later merging PR #195 cannot restore the retired FILE_CONTROL files; do not mutate #195 merely as migration preparation.

## Work and ownership boundary

Allowed now: this migration branch's governance/control/documentation files, GitHub Issue drafts and one Draft migration PR. Preserve exact source and tests for WebKit, Window/Focus, Profile/session persistence, CI runner and the separate #195 task branch/worktrees. Use the smallest safely reusable checkout; no extra physical worktree required solely for documentation.

**STOP:** unknown local writer/unique work, missing local `gh` proof, missing trusted digest-bound approval, a still-executable task without a complete Issue, unexpected CI/PR gate, or any attempt to treat unmerged draft files as active ISSUE_CONTROL. Keep migration PR Draft, FILE_CONTROL active, and report `CUTOVER_READY=NO` until each gate is demonstrably satisfied.

## Verification / handoff

- Focused read of GitHub ref, PR #195 current branch task, Issue spec bodies, official structural validator, and actual approval comment provenance.
- No product CI necessary for preparation-only documentation changes; apply applicable host checks to the literal final migration PR head before merge.
- Human product-UI acceptance is not required for this control-only migration, but remains **PENDING** for #195's separate product task.
- Issue comment receipts must be verifiably posted, not inferred from local text. Include true `REMOTE_DELIVERY`, `CONTROL_ALIGNMENT`, `PR`, `CUTOVER_BASIS`, `LOCAL_GH_PREFLIGHT`, `SPEC_APPROVAL`, `NEXT_SAFE_ACTION` in final receipt.
