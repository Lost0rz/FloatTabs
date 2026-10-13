# FloatTabs Current Task

**Task ID:** `FT-PR-CLOSEOUT-001`
**Title:** Reconcile and close retained PR lifecycle
**Status:** `ACTIVE`
**Mode:** `PR_LIFECYCLE_RECONCILIATION`

## Objective

Reconcile the two retained open Draft PRs against current `main`, preserve still-valid product work, and give each PR an explicit terminal disposition before any new global code audit.

Process in order:

1. PR #116 — `fix/residency-lifecycle-semantics`;
2. PR #102 — `phase2/pr-e-floattabs-durable-outbox-sender`.

Do not start #102 state-changing reconciliation until #116 is terminal.

## Authority / scope

Primary authority is repository/PR lifecycle plus the domains already changed by each PR.

In scope:

- fresh base/head/diff/conflict/CI/review evidence;
- determine which PR changes remain valid against current `main`;
- resolve conflicts using the existing PR when safe;
- preserve task-owned corrections that remain semantically valid;
- proportional focused tests and required CI;
- relevant real-mac runtime acceptance for Web/runtime lifecycle changes;
- terminal PR/workspace disposition and control-plane reconciliation.

Out of scope:

- unrelated new product fixes;
- broad architecture refactors;
- new diagnostics unless required to verify the retained PR itself;
- global code audit before both retained PRs are terminal;
- opening overlapping successor PRs merely to avoid reconciling an existing predecessor.

Adjacent issues found during reconciliation become Follow-ups only.

## PR #116 acceptance

Before terminal disposition, establish against current `main`:

- exact remaining semantic diff;
- Hot inactive renderer-recovery contract;
- Warm TTL contract with no ordinary two-Warm cap;
- memory-pressure warning vs critical behavior;
- media / attention / speech protections unchanged;
- focused lifecycle tests;
- relevant macOS runtime acceptance;
- required exact-head GitHub CI and mergeability.

If still valid and safely reconcilable, prefer completing PR #116 rather than replacing it. Otherwise give it an explicit non-merge terminal disposition with evidence.

## PR #102 acceptance

After #116 is terminal, establish against the then-current `main`:

- whether the MemoX integration is still wanted and contract-compatible;
- exact remaining semantic diff and current dependency/receiver assumptions;
- no regression to FloatTabs runtime, response ownership, persistence, or user-data safety;
- focused tests plus any required cross-repository E2E evidence;
- required exact-head CI and mergeability.

Then give PR #102 an explicit terminal disposition.

## STOP conditions

STOP and report before mutation if:

- a retained branch contains unknown/unique work not explained by its PR;
- current `main` materially invalidates the PR's accepted product contract;
- reconciliation would require unrelated product scope;
- task-relevant Authority cannot be established safely;
- required runtime or repository-host evidence fails.

## Workspace / branch expectation

Use the existing PR branch as the default writer for that PR. Do not create a new overlapping branch/worktree unless fresh evidence proves the predecessor cannot be safely continued. Preserve unknown local or remote work.

## Task completion

This task is terminal only when both retained PRs are explicitly one of:

- `MERGED`
- `SUPERSEDED`
- `ABANDONED`
- `ARCHIVE_ONLY`

Then reconcile `CURRENT_STATUS.md` / `CURRENT_TASK.md`, confirm the resulting clean baseline, and set the next milestone to a fresh global read-only audit.
