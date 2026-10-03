# FloatTabs Current Task

**Task ID:** FT-GOV-001  
**Title:** Establish authoritative cross-surface project state  
**Status:** ACTIVE  
**Mode:** DOCS / READ-ONLY RECONCILIATION

## Objective

Adopt a three-file control plane so ChatGPT/web and local development agents share
the same project state without reconstructing it from conversation history:

- `AGENTS.md` — durable rules;
- `CURRENT_STATUS.md` — authoritative intended state and classifications;
- `CURRENT_TASK.md` — the single authorized task.

The task is not complete merely because the files exist. It completes when the
local repository/worktree state has been reconciled and exactly one authoritative
production worktree identity is bound in `CURRENT_STATUS.md`.

## Authorized work

The following work is allowed:

1. Create, review, and refine the three control-plane files.
2. Update PR #103 metadata to describe this control-plane scope.
3. Perform read-only Git/GitHub inventory of branches, PRs, commits, worktrees,
   status, and upstream relationships.
4. Classify existing PRs/worktrees without changing production behavior.
5. Choose one authoritative clean production worktree identity only after the
   inventory proves its branch/HEAD/upstream relationship.
6. Update `CURRENT_STATUS.md` with the verified logical worktree ID, branch/ref
   contract, and any corrected classifications. Keep machine-specific absolute
   paths out of the public repository.
7. After local reconciliation and final docs review, manually dispatch the existing
   `macOS CI` workflow on the exact #103 governance branch HEAD so the required
   `Build & Test (Apple Silicon arm64)` branch-protection check can run. Do not
   install or release the resulting build.

A governance checkout may be used to edit these three documents. It does not
become the production worktree merely by hosting PR #103.

## Explicitly prohibited

Until this task changes state, do **not**:

- fix the WebKit stuck-tab bug;
- add or expand runtime logs, probes, counters, or diagnostics;
- add new recovery behavior;
- modify production Swift/runtime behavior;
- rebuild, reinstall, or replace the running QA app as part of this task;
- perform a runtime reset or controlled incident experiment;
- merge #99, #100, #101, #102, #87, #94, or #96;
- create a new bug-fix/diagnostic PR on top of the unresolved stack;
- use a different local checkout as a production worktree because the requested
  worktree is missing;
- infer current state from Memory/chat when it conflicts with the control-plane
  files.

## Recorded baseline

- Remote `main`: `a94ae46db756b10014651f3639cf8659917e204b`
- Governance PR: #103
- Governance branch: `codex/project-agents-control-plane-v1`
- Runtime investigation stack: #99 → #100 → #101, all frozen
- Authorized production worktree ID: **NONE**
- Previous requested worktree: confirmed missing on the machine where the
  baseline gate ran; no replacement was authorized. Exact local paths remain
  local-only and are not part of the public repository contract.

## Required local reconciliation procedure

Before interpreting local state, refresh remote refs read-only. Then produce one
compact **local audit** table for every discovered FloatTabs worktree with:

- absolute path (local audit output only; do not commit it);
- branch or DETACHED;
- HEAD;
- upstream ref and upstream HEAD if present;
- clean/dirty state;
- associated PR if any;
- classification;
- whether it is eligible to become the authoritative production worktree.

Also verify the live remote refs for `main`, #99, #100, #101, #102, #87, #94,
and #96 against the recorded snapshots in `CURRENT_STATUS.md`. For #103, apply
its dynamic governance-branch HEAD verification contract rather than expecting a
self-recorded SHA.

If a remote head differs from the recorded snapshot, report the mismatch and
update/reconcile `CURRENT_STATUS.md` before any implementation work.

## Acceptance criteria

FT-GOV-001 is complete only when all of the following are true:

- all three control-plane files exist and have non-overlapping roles;
- the remote main baseline and relevant open PR stack are recorded;
- live-ref authority versus state-contract authority is unambiguous;
- confirmed incident facts are separated from hypotheses;
- exactly one production worktree identity is recorded as authoritative;
- its branch/ref contract is recorded, while its locally resolved path, HEAD,
  upstream, and clean state are verified after remote refresh;
- unresolved worktrees/PRs have explicit classifications;
- a new agent can detect a checkout or ref mismatch and STOP without guessing;
- no production/runtime behavior was changed while establishing the control plane;
- the exact governance HEAD proposed for merge has a passing
  `Build & Test (Apple Silicon arm64)` required check.

## Stop / handoff condition

After local reconciliation, update `CURRENT_STATUS.md` and this task together if
the task state changes.

If the state is clean and unambiguous and the exact merge HEAD satisfies the
required branch-protection check, FT-GOV-001 may be marked COMPLETE and the next
task may be created. The next task must be chosen from reconciled facts; it
must not automatically resume bug fixing or log expansion.
