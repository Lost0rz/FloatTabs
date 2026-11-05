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

## Verified pre-cutover progress (2026-11-05)

- **WP01 COMPLETE:** Installed Engineering Governance v0.8.1 official `issue-spec-check.py digest` returned `STRUCTURE_PASS_APPROVAL_PENDING` for #197 revision 1 SHA256 `48e547e9b8e045c1b422d36066e045d05fb9d18a9d8d1471bb4c35d636d44c8c` and #198 revision 1 SHA256 `41458ae8ea9f0a5c9b66615d819ccb79b5c5b6422fcbdefcf3e565cf14547bd2`. Local `gh` authenticated as `Lost0rz` and posted/fetched [CLI test comment #6659119976](https://github.com/Lost0rz/FloatTabs/issues/197#issuecomment-6659119976).
- **Remote routing/document reconciliation prepared:** this same Draft PR updates `AGENTS.md` with literal `CONTROL_MODE: FILE_CONTROL` and proposed `ISSUE_APPROVERS: Lost0rz`; it refreshes `docs/README.md`, `docs/architecture/README.md`, `docs/architecture/DOMAIN_MAP.md` and stale directory/readme authority references. Historical evidence is retained. The effective main mode is still FILE_CONTROL.
- **WP02 BLOCKED:** Trusted `SPEC_APPROVAL_V1` comments for both exact digests are absent. An agent must not author an approval through the connected `Lost0rz` credential. The independent PR #195 local branch has four modified tracked files and one untracked fixture, seven commits behind remote; its writer/unique-work disposition remains unverified. Do not stash, reset, delete, checkout-overwrite or merge it.
- **CUTOVER_READY=NO:** do not set `AGENTS.md: ISSUE_CONTROL` and retire root Task/Status until all required approvals/ownership/host gates are verified. The final switch and the file retirements must be one exact controlled PR transaction.

## Work and ownership boundary

Allowed now: this migration branch's governance/control/documentation files, GitHub Issue drafts and one Draft migration PR. Preserve exact source and tests for WebKit, Window/Focus, Profile/session persistence, CI runner and the separate #195 task branch/worktrees. Use the smallest safely reusable checkout; no extra physical worktree required solely for documentation.

**STOP:** unknown local writer/unique work, missing local `gh` proof, missing trusted digest-bound approval, a still-executable task without a complete Issue, unexpected CI/PR gate, or any attempt to treat unmerged draft files as active ISSUE_CONTROL. Keep migration PR Draft, FILE_CONTROL active, and report `CUTOVER_READY=NO` until each gate is demonstrably satisfied.

## Verification / handoff

- Focused read of GitHub ref, PR #195 current branch task, Issue spec bodies, official structural validator, and actual approval comment provenance.
- No product CI necessary for preparation-only documentation changes; apply applicable host checks to the literal final migration PR head before merge.
- Human product-UI acceptance is not required for this control-only migration, but remains **PENDING** for #195's separate product task.
- Issue comment receipts must be verifiably posted, not inferred from local text. Include true `REMOTE_DELIVERY`, `CONTROL_ALIGNMENT`, `PR`, `CUTOVER_BASIS`, `LOCAL_GH_PREFLIGHT`, `SPEC_APPROVAL`, `NEXT_SAFE_ACTION` in final receipt.
