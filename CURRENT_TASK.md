# FloatTabs Current Task

**Task ID:** `FT-GOV-BOOTSTRAP-001`
**Title:** Establish lightweight governance and Domain Map
**Status:** `TERMINAL`
**Mode:** `GOVERNANCE_BOOTSTRAP_COMPLETE`

## Objective

Establish a verified, lightweight project control plane and derived Domain Map so FloatTabs can resume normal governed development from a clean baseline.

## Result

Completed:

- refreshed governance rules in `AGENTS.md`;
- established `docs/architecture/DOMAIN_MAP.md`;
- linked current architecture navigation through `docs/architecture/README.md`;
- reconciled `CURRENT_STATUS.md` to `READY_FOR_DEVELOPMENT`;
- preserved PR #116 and PR #102 as inactive/deferred work;
- made no product-source or test changes.

## Baseline / Workspace

```text
AUDIT_BASE=main@d685bbe7c035332ecc9b7ab6f8641660f813d42f
WORK_BRANCH=governance/floattabs-domain-bootstrap-20261013
PRODUCT_SOURCE_CHANGED=NO
TESTS_CHANGED=NO
```

The `8fd1aa... -> d685bbe...` movement was lifecycle/control documentation only and did not create a new product delivery identity.

## Acceptance

- Domain/source/test navigation is available without reconstructing repository structure from chat history.
- Control-plane roles and task lifecycle are explicit and lightweight.
- Repository HEAD and Delivery / Semantic HEAD are distinguished.
- Runtime incidents preserve evidence/root-cause separation.
- The project can accept the next bounded product objective after this governance branch is integrated.

## Authorization after closeout

There is **no active product-development task** in this file.

The next state-changing product task must:

1. refresh task-relevant repository evidence;
2. select the affected Domain/Authority using the Domain Map;
3. update `CURRENT_TASK.md` with the new objective/scope/acceptance/STOP conditions;
4. only then mutate product source or tests.

Do not regenerate this bootstrap task when the user later says “continue”.

## Final state

```text
TASK=TERMINAL
PROJECT=READY_FOR_DEVELOPMENT
NEXT_PRODUCT_TASK=NOT_YET_AUTHORIZED
```
