# FloatTabs Current Task

**Task ID:** `FT-GOV-BOOTSTRAP-001`
**Title:** Establish lightweight governance and Domain Map
**Status:** `ACTIVE`
**Mode:** `GOVERNANCE_BOOTSTRAP`

## Objective

Establish a verified, lightweight project control plane and derived Domain Map so FloatTabs can resume normal governed development from a clean baseline.

## Authority / Scope

Affected authority: project governance and repository navigation only.

In scope:

- reconcile the current `main` baseline and retained PR lifecycle;
- refresh `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md` where needed;
- create a concise derived Domain Map from current source/docs/tests;
- identify canonical domains, primary source entry points, test locations, and authority boundaries;
- leave the repository in `READY_FOR_DEVELOPMENT` state.

Out of scope:

- product/runtime behavior changes;
- source or test implementation changes;
- advancing, merging, or deleting PR #116 or PR #102;
- release work;
- incident/root-cause diagnosis.

## Baseline

```text
REPOSITORY=Lost0rz/FloatTabs
LIVE_MAIN=d685bbe7c035332ecc9b7ab6f8641660f813d42f
WORK_BRANCH=governance/floattabs-domain-bootstrap-20261013
OPEN_DEFERRED_PRS=#116,#102
```

The `8fd1aa... -> d685bbe...` main movement is lifecycle/control documentation only; it does not represent a new product delivery identity.

## Verification / Acceptance

- Domain Map is evidence-backed and points to current source/test/document locations.
- Control files agree on baseline, lifecycle, and readiness state.
- No product source or tests are changed.
- Deferred PRs remain explicitly inactive.
- Final state is ready for a future product task without requiring chat-history reconstruction.

## STOP Conditions

STOP if fresh evidence shows:

- `main` moved with implementation-relevant changes during this task;
- a retained PR/workspace contains unknown overlapping authority that blocks clean governance;
- a Domain/Authority cannot be mapped safely from current evidence;
- requested work would require product/runtime mutation.

## Lifecycle

Current state: `ACTIVE_GOVERNANCE_BOOTSTRAP`.

On completion, reconcile `CURRENT_STATUS.md` and this file. The next product-development task must be separately authorized before source mutation.
