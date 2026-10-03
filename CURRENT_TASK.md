# FloatTabs Current Task

**Task ID:** FT-GOV-001  
**Title:** Establish authoritative cross-surface project state  
**Status:** ACTIVE  
**Mode:** DOCS / READ-ONLY RECONCILIATION

## Objective

Create and adopt a three-file control plane so ChatGPT/web and local development
agents share the same project state without reconstructing it from conversation
history:

- `AGENTS.md` — durable rules;
- `CURRENT_STATUS.md` — authoritative current state;
- `CURRENT_TASK.md` — the single authorized task.

The task is not complete merely because the files exist. It completes when the
local repository/worktree state has been reconciled and exactly one authoritative
worktree is bound in `CURRENT_STATUS.md`.

## Authorized work

The following work is allowed:

1. Create, review, and refine the three control-plane files.
2. Update PR #103 metadata to describe this control-plane scope.
3. Perform read-only Git/GitHub inventory of branches, PRs, commits, worktrees,
   status, and upstream relationships.
4. Classify existing PRs/worktrees without changing production behavior.
5. Choose one authoritative clean worktree only after the inventory proves its
   branch/HEAD relationship.
6. Update `CURRENT_STATUS.md` with the verified authoritative worktree and any
   corrected classifications.

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
- use a different local checkout because the requested worktree is missing;
- infer current state from Memory/chat when it conflicts with the three files.

## Baseline

- Remote `main`: `a94ae46db756b10014651f3639cf8659917e204b`
- Governance PR: #103
- Governance branch: `codex/project-agents-control-plane-v1`
- Runtime investigation stack: #99 → #100 → #101, all frozen
- Authorized local worktree: **NONE**
- Last requested worktree:
  `/Users/jack7788/.codex/worktrees/web-runtime-reset-validation/FloatTabs`
  — confirmed missing; baseline gate stopped.

## Required local reconciliation output

The local agent must produce one compact table with, for every discovered FloatTabs
worktree:

- absolute path;
- branch or DETACHED;
- HEAD;
- upstream ref and upstream HEAD if present;
- clean/dirty state;
- associated PR if any;
- classification;
- whether it is eligible to become authoritative.

It must also verify the remote refs for `main`, #99, #100, #101, #102, #103,
#87, #94, and #96.

## Acceptance criteria

FT-GOV-001 is complete only when all of the following are true:

- all three control-plane files exist and have non-overlapping roles;
- remote main HEAD and the relevant open PR stack are recorded;
- confirmed incident facts are separated from hypotheses;
- exactly one local worktree is recorded as authoritative;
- its path, branch, HEAD, upstream, and clean state are verified;
- unresolved worktrees/PRs have explicit classifications;
- a new agent can detect a checkout mismatch and STOP without guessing;
- no production/runtime behavior was changed while establishing the control plane.

## Stop / handoff condition

After local reconciliation, update `CURRENT_STATUS.md` and this task.

If the state is clean and unambiguous, FT-GOV-001 may be marked COMPLETE and the
next task may be created. The next task must be chosen from the reconciled facts;
it must not automatically resume bug fixing or log expansion.
