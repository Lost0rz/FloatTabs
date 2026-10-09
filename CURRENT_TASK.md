# FloatTabs Current Task

**Task ID:** `NONE`
**Title:** No active product-development task
**Status:** `PAUSED`
**Mode:** `OBSERVATION_ONLY`

## Authority

There is currently no authorized FloatTabs product-development task.

The previous task, FT-SPEECH-001, is closed because PR #115 merged into `main`.

```text
FT_SPEECH_001=CLOSED_MERGED
PR_115_HEAD=c7409a565d8a1fb76c540df9e1fe5f3bb702f50d
MERGE_HEAD=569e43783a98c8caca681ce8139ec87dd4fa276e
```

The former FT-SPEECH-001 merge-gate instructions are historical only and must not authorize new work.

## Current project posture

Short-term development is paused. Continue normal use and observation. Start development again only when the user reports a real issue or explicitly authorizes a new objective.

## Retained but inactive work

- PR #116 / `fix/residency-lifecycle-semantics`: retained OPEN / DRAFT at last verification, head `8e86f22e8a3e088a1e3fd6c53cffd3eebeedc9ef`; **DEFERRED**, not current authority.
- PR #102 / `phase2/pr-e-floattabs-durable-outbox-sender`: retained OPEN / DRAFT at last verification, head `db6e886b33dffd93ece130463b184ae371b97684`; **DEFERRED**, not current authority.

Do not infer authorization from an existing branch, worktree, draft PR, old control file, or cached local history.

## Authorized now

```text
NORMAL_USE=YES
OBSERVATION=YES
READ_ONLY_AUDIT=YES
FRESHNESS_CHECK=YES
PRODUCT_CHANGE=NO
TEST_CHANGE=NO
DIAGNOSTIC_EXPANSION=NO
PR_PROGRESS=NO
MERGE=NO
RELEASE=NO
```

## Resume gate

Before any future state-changing work:

1. receive a new user-reported issue or explicit development objective;
2. refresh live Git/GitHub state;
3. establish the selected physical workspace, branch/ref, HEAD, and working-tree state;
4. determine whether any retained PR/branch/worktree is relevant to the new objective;
5. write a fresh task authorization with bounded scope, acceptance, STOP conditions, and required verification;
6. only then begin implementation.

If a future real problem is evidence-deficient, use the minimum decision-linked incident investigation rather than expanding diagnostics speculatively.

## Final state

```text
FINAL_STATE=PAUSED_NO_ACTIVE_DEVELOPMENT_TASK
```
