# FloatTabs — Documentation Authority and Status Index

> Durable documentation router, **not** live task authorization. Resolve the accepted `main` `AGENTS.md` mode before any source-changing work.

## Effective authority

```text
AGENTS.md (main): CONTROL_MODE + durable safety + ISSUE_APPROVERS
  FILE_CONTROL → authorized CURRENT_TASK.md / verified CURRENT_STATUS.md
  ISSUE_CONTROL → selected, verified, approved GitHub EXECUTION_SPEC_V1 Issue
→ linked accepted design/architecture contract for bounded product semantics
→ docs/architecture/README.md and docs/architecture/DOMAIN_MAP.md for navigation
→ production source, regression tests, current Git/CI/runtime evidence
```

An Issue body is a task contract, not canonical code or design truth. An Issue comment is progress evidence, not implicit authorization. A handoff card does not add scope. The official Engineering Governance `project-governance` capability governs the migration and approval process. Older Task/Status files remain authority **only while main is in FILE_CONTROL**; after verified ISSUE_CONTROL cutover, they are retired rather than duplicated.

## Current transition — dated snapshot (2026-11-05)

- [Issue #197](https://github.com/Lost0rz/FloatTabs/issues/197): governance migration (pre-cutover planning, original `TASK_ID=FT-GOV-ISSUE-CONTROL-MIGRATION-001`).
- [Issue #198](https://github.com/Lost0rz/FloatTabs/issues/198): carry-forward of active `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` product task.
- [Draft PR #199](https://github.com/Lost0rz/FloatTabs/pull/199): **the only governance migration PR**. Its branch contents do not activate ISSUE_CONTROL.
- [Draft PR #195](https://github.com/Lost0rz/FloatTabs/pull/195): independent adaptive-lifecycle/cold-restore corrective. Its head-aligned Task evidence describes human UI acceptance **PENDING** at this observation; preserve the dirty local checkout and unique work.
- PR #196 was already merged at `d64c9ec6`. Its older pending-merge snapshot must not control a new task.
- Official Issue digests and local `gh` read/write were reported PASS in [#197 CLI receipt](https://github.com/Lost0rz/FloatTabs/issues/197#issuecomment-6659119976); **neither Issue has a verified trusted `SPEC_APPROVAL_V1`**. Exact digests must always be retrieved fresh before approving/executing.
- Outstanding gates: confirm the local PR #195 worktree's writer/unique-work disposition; receive two independently authenticated exact-spec approvals; stage and verify one atomic `AGENTS.md` mode switch + Task/Status retirement; pass applicable host gates; verify merge on main.

**This dated snapshot can go stale.** For the current task/state always read live Issue, PR, commit and applicable authority; do not treat the historical observations here as HEAD locks.

## Current accepted architecture and boundaries

Read [architecture/README.md](architecture/README.md) for selected architectural contracts and [architecture/DOMAIN_MAP.md](architecture/DOMAIN_MAP.md) for source/test entry points. The accepted `FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md` is a bounded design contract; its former WP1 gate does **not** independently authorize new execution. The more recent #195 branch Task/CI evidence governs that *branch's* currently observed corrective until the Issue migration is complete. Source/tests remain implementation truth.

Preserve:

- Slot/Browser Profile persistence separate from disposable WKWebView runtimes;
- `SlotLifecycleCoordinator` as sole lifecycle policy/reclaim writer; `WebViewPool` as runtime mechanism owner;
- native restoring presentation and exact-current readiness before exposing an unready cold runtime;
- generation protection, unread/notification exact-Slot behavior and human UI acceptance;
- progressive warning/critical memory-pressure behavior;
- Phase 8 public WebContent/GPU attribution limitation: do not replace a real RAM budget with Runtime count or private APIs.

Do not classify `reload/reset/restart fixed it` as a proven root cause or destroy website/user data as recovery.

## Directory status

| Directory | Role |
| --- | --- |
| `docs/architecture/` | Accepted bounded contracts, historical architecture decisions and current source routing |
| `docs/architecture/archive/` | Historical snapshots; non-authoritative |
| `docs/design/` | Bounded UI interaction contracts plus historical references |
| `docs/product/` | Historical feature/Stage plans and bounded feature concepts |
| `docs/diagnostics/` | Evidence, not product truth or root-cause authority |
| `docs/performance/` | Historical benchmarks; phase-specific measurements only when newly accepted |
| `docs/validation/` | Historical acceptance snapshots, never current UI verdict |
| `docs/release/` | Historical version-specific evidence; GitHub current releases are host truth |
| `docs/superpowers/` | Legacy plans, never a live execution framework |
| `docs/uiux/` | Visual references, not live interaction or task authority |

Historical contracts, Stage documents, plans and audits are **retained intact** as evidence. Their terms `CURRENT`, `LOCKED`, `IMPLEMENTED`, `ACCEPTED` and `NEXT` refer to the time/phase when authored, unless accepted current authority explicitly says otherwise. Do not bulk-delete or rewrite them to retroactively change history.

## Conflict and continuation

1. Use the mode-selected Task/approved Issue for execution *permission*, accepted bounded design for semantics, and fresh source/tests/host facts for what is actually true.
2. If a historic WP claim contradicts current code/branch evidence, treat it as superseded, not as new permission.
3. Preserve independent PR #195 and any local uncommitted/unique files. Never clean a worktree to simplify governance.
4. Keep non-approved Issues design-only; no `SPEC_APPROVAL_V1` comment may be fabricated through an agent using the approver's account.
5. A verified merge of the migration PR is the sole control-mode cutover. Until then, maintain FILE_CONTROL; afterwards do not resurrect legacy root controls.
