# FloatTabs Current Task

**TASK_ID:** FT-PANEL-CROSS-DISPLAY-001  
**TASK_CLASS:** CORRECTIVE / FINAL CLOSEOUT  
**STATE:** HUMAN_ACCEPTED / FINAL_MERGE_AUTHORIZED / REPOSITORY_GATES_PENDING  
**BRANCH:** `codex/panel-cross-display-position-001`  
**PR:** #196 — https://github.com/Lost0rz/FloatTabs/pull/196

## Current authorization

The user explicitly confirmed human acceptance of corrective 005 and requested that PR #196 be updated, merged, and the current Panel corrective task closed on 2026-11-04. This is final repository delivery and closeout authorization only, not additional product-change authorization.

Applicable authority: `AGENTS.md`, `CURRENT_STATUS.md`, this file, accepted current Panel/Focus contracts and production source/tests. Retain the code implementation `a39b87a91be60f70c40cf8b600f5b3b7725f6568` and its related corrective history in Git.

## Merge gate

1. Reconfirm fresh `main`, branch, PR base/head, unique work, mergeability, exact changed-file scope, and no interference with PR #195.
2. Accept the user's explicit `HUMAN_UI_ACCEPTANCE=PASS` for the implemented Panel corrective. Do not claim individual scenario details not reported.
3. Verify required arm64 CI, QA DMG and any host-governed checks for the literal PR identity. Implementation-head macOS CI/QA passed on `a39b87a`; a newer control-only commit does not change product semantics but must still satisfy applicable GitHub-hosted gates before merging.
4. Align the existing PR head to the final branch commit without force pushes or deleting unique work. If GitHub still reports an inconsistent/stale PR head, STOP instead of merging an older subset.
5. When all gates pass, mark #196 Ready and merge using an allowed normal repository method. Do not merge #195 or release a public build.
6. Verify fresh `origin/main` (GitHub ref) includes the complete #196 implementation and closeout controls. Reconcile main's terminal `CURRENT_STATUS.md` / `CURRENT_TASK.md` without spawning a new product task, PR, or worktree solely for closeout, subject to repository protection.

## Outcome boundary

- Human accepted product behavior; system-level cross-Space focus-selection root cause remains `UNKNOWN`.
- No additional Panel feature/corrective work is authorized during closeout.
- Future reproducible incidents: existing Diagnostics → evidence review → new task only if needed.
- PR #195 remains a separate OPEN/DRAFT adaptive-lifecycle task, untouched.

**STOP:** any divergent branch/PR identity, unknown unique work, required CI failure, merge conflict, unexpected additional code change, or inability to verify main contains the intended PR head.
