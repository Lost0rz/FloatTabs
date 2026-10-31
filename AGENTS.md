# FloatTabs Agent Instructions

FloatTabs is a native macOS browser container. Engineering priority is:

**user experience / stability → runtime correctness → diagnosability → governance**.

Do not expand governance, telemetry, or generic frameworks ahead of actual product needs.

## Control plane

Repository authority uses:

- `AGENTS.md` — durable project rules and authority boundaries;
- `CURRENT_STATUS.md` — verified current-state snapshot;
- `CURRENT_TASK.md` — the only active task authorization;
- `docs/README.md` — documentation authority/status routing index;
- `docs/architecture/DOMAIN_MAP.md` — derived navigation map, not product truth or task authority.

Chat history, Memory, handoff cards, audit replies, historical reports, old PRs, and archived documents are supporting evidence only.

Before state-changing work, read the three control files, refresh the task-relevant repository evidence, and confirm the requested work is authorized by `CURRENT_TASK.md`.

When consulting repository documentation beyond the three control files, read `docs/README.md` before relying on old architecture/product/design/validation/plan files. A historical document does not regain current Authority because its body says `FROZEN`, `LOCKED`, `canonical`, `accepted`, `implemented`, `current`, or `CONSTRUCTION_GATE_READY`.

If the user says “continue” and the active task is still accurate, continue it. Do not generate a second execution contract.

A materially new objective, scope, Authority, acceptance rule, STOP condition, or workspace owner requires task reconciliation before mutation.

## Repository identity

Distinguish:

- **Repository HEAD** — literal current commit;
- **Delivery / Semantic HEAD** — implementation identity being verified.

A commit changing only `CURRENT_STATUS.md` / `CURRENT_TASK.md` is `CONTROL_ONLY_DRIFT`. It does not by itself invalidate product implementation evidence or require a new task/PR/test cycle.

Do not treat every historical recorded SHA as a permanent equality lock. Fresh Git/GitHub refs are authoritative for current branch/PR identity.

Preserve unknown staged, unstaged, untracked, local-only, or archived work. Never reset/delete it merely to make a workspace match an expected state.

## Documentation status / history boundary

Historical documentation is preserved as evidence, rationale, and release/acceptance history. It is not a parallel control plane.

Treat these as historical by default unless current Authority explicitly restores a claim:

- Stage-numbered design/product/validation documents;
- dated plans and `docs/superpowers/plans/*`;
- construction plans after their task/feature closed;
- point-in-time audits;
- old product specs and old technical architecture versions;
- old benchmark protocols tied to superseded lifecycle/product models;
- release records;
- anything under an `archive/` directory.

Accepted feature contracts may remain useful for their bounded feature semantics, but when they overlap a newer cross-cutting contract or current production source/tests, the newer/current owner wins.

Do not rewrite historical evidence into present-day facts merely to make documents look consistent. Prefer a status wrapper/banner plus an archive copy of the original body when an old document's current-sounding wording could mislead future work.

## Domain / Authority boundaries

Use `docs/architecture/DOMAIN_MAP.md` for navigation. Key durable boundaries:

- **Tabs** own Tab/Profile identity, selection, ordering, and configuration projection.
- **Web** owns `WKWebView` runtime, navigation, residency, observer/task lifecycle, runtime health, and recovery.
- **Panel / Window / Fullscreen** own presentation and window synchronization.
- **Focus / Input** own native/DOM focus and command/event routing.
- **Persistence** owns durable user configuration and recovery data.
- **Speech / Attention** consume bounded runtime/content signals; they do not become Tab/Web authorities.
- **Diagnostics** record evidence; logs do not become product truth or root-cause authority.

Keep one writer per canonical state. Do not use persistence to hide runtime bugs or reload to hide runtime-ownership problems.

## Governance routing

Normal repository engineering enters through:

`engineering-governance → project-governance`

Use `domain-navigation` only when the affected Domain, Authority, source location, runtime entry, dependency, or relevant tests cannot be established safely.

Use `incident-doctor` only when a real runtime failure blocks progress and existing evidence is insufficient for the next safe decision. A normal UI bug or evidence-backed defect stays in normal governed development.

## Task lifecycle

### Start

Before state-changing execution:

1. read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. refresh task-relevant refs/evidence;
3. verify current task scope and relevant workspace/branch/PR identity;
4. stop on material authority ambiguity or unknown overlapping unique work.

A truly new task must first be authorized in `CURRENT_TASK.md`.

### Phase / design execution gate

For a multi-phase architecture or other high-risk program governed by an accepted design/architecture contract, do not jump from the high-level phase description directly into product mutation.

Before each implementation phase:

1. reread the active contract plus `CURRENT_STATUS.md` / `CURRENT_TASK.md`;
2. perform a focused read-only audit of the exact production owners, call paths, lifecycle/retain boundaries, existing tests, and fresh repository evidence relevant to that phase;
3. freeze the phase's concrete scope, expected files/symbols, verification matrix, acceptance criteria, and STOP conditions in repository Authority when they materially change the task;
4. only then issue a concise execution card for the local executor;
5. keep the execution card bounded and avoid duplicating the full repository contract.

After implementation, run focused verification and independent audit before merge/closeout. A chat plan or execution card never overrides the accepted repository contract or `CURRENT_TASK.md`.

### During

Do not expand the task for adjacent issues. Record material non-blocking items as Follow-ups in `CURRENT_STATUS.md`; they become executable only through a future task authorization.

If implementation introduces or changes canonical ownership, writers, shared behavior, module boundaries, or a materially new responsibility, re-check the code-structure boundary before continuing.

### Completion

Every terminal task must run a Control Alignment Gate before successful handoff:

- obtain fresh outcome evidence;
- reread STATUS and TASK;
- update only control facts whose owned semantics materially changed;
- close or explicitly retain task-relevant workspace/PR lifecycle state.

A task is not fully closed merely because its PR merged.

## PR / branch / worktree lifecycle

Default to one writer for overlapping Authority.

A correction that still belongs to the current task should normally stay in the current PR. Do not open a new PR/worktree for every discovered defect.

Before establishing an overlapping successor, resolve a predecessor that remains write-capable, lifecycle-unclear, or contains unknown unique work.

Diagnostic/experimental PRs must eventually have a clear disposition such as `MERGED`, `SUPERSEDED`, `ABANDONED`, or `ARCHIVE_ONLY`.

Routine continuation does not require re-inventorying every historical branch/worktree; inspect the task-relevant lifecycle only.

## Runtime / incident evidence

Keep separate:

- symptom / observation;
- recovery behavior;
- causal evidence;
- experimental mitigation;
- production fix.

For incidents, correlate evidence where available by source/build identity, Slot, session, runtime generation/WebView instance, navigation generation, timestamps, and recovery request/result.

`reload fixed it`, `reset fixed it`, or `restart fixed it` identifies a recovery boundary only. It does not prove root cause.

If evidence is insufficient, preserve:

`ROOT CAUSE UNKNOWN`

Do not combine stale events from different runtime/navigation generations as one incident.

## Verification

Verification effort follows risk, not change count.

Use focused tests first. Increase verification for changes involving:

- WebView lifecycle / navigation;
- observer cleanup / task cancellation;
- runtime reset / recovery;
- window / fullscreen ownership;
- focus / event monitors;
- persistence / migration;
- canonical state writers.

Real macOS interaction/runtime changes require relevant runtime acceptance; static review alone is insufficient.

Before merge/release, separately confirm current PR base/head, exact diff, required CI, reviews/mergeability, task scope, Authority integrity, and applicable runtime acceptance. Repository-host gates apply to the literal identity GitHub governs and cannot be inferred from older semantic evidence.

## Product-data safety

Browser Profiles, Web App Slot configuration, persisted website/session data, preferences, backups, and recovery material are user/product data.

Do not delete/reset them or replace unreadable persisted configuration with an empty fallback merely to recover runtime behavior unless the active task explicitly authorizes that behavior and its data-loss implications.

## Stop conditions

STOP and report evidence when:

- active task authorization is missing or materially stale;
- the requested mutation is outside task scope;
- task-relevant baseline/Authority changed materially;
- an overlapping predecessor contains unknown unique work;
- a required live repository-host gate fails;
- a linked design/plan change invalidates task acceptance or scope;
- safe ownership cannot be established without further navigation/incident evidence.

Do not stop merely because Repository HEAD advanced only through control-plane changes with unchanged task semantics.

## Final Status Receipt

Engineering governance, implementation, audit, CI, PR, merge, release, and status replies end with:

```text
Governance: engineering-governance → project-governance
Skills used: <actual skills>
Router: default / domain-navigation / incident-doctor
Task state: <ACTIVE / WAITING / TERMINAL / N/A>
Root cause: <KNOWN / UNKNOWN / N/A>
Merge: <MERGED / NOT MERGED / N/A>
Updated files: <files or NONE>
Control plane: STATUS=<UPDATED/UNCHANGED/STALE>, TASK=<UPDATED/UNCHANGED/STALE>
PR / workspace: <state or N/A>
Final state: <short result>
```

Only report Skills actually used. If no merge occurred, say `NOT MERGED`; if no files changed, say `NONE`; if STATUS/TASK should have changed but did not, say `STALE`. For unresolved runtime failures, keep `Root cause: UNKNOWN`.

The receipt is status visibility only; it never becomes repository Authority.
