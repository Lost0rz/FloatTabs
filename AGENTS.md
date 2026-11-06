# FloatTabs Agent Instructions

FloatTabs is a native macOS browser container. Engineering priority is:

**user experience / stability → runtime correctness → diagnosability → governance**.

Do not expand governance, telemetry, or generic frameworks ahead of actual product needs.

## Control plane

CONTROL_MODE: ISSUE_CONTROL
ISSUE_APPROVERS: Lost0rz

The mode declared here is authoritative **only when this file is verified on `main`**. An unmerged branch, draft PR, installed plugin, GitHub Issue or CLI success does not switch the effective mode. The cutover transaction also retires root `CURRENT_TASK.md` and `CURRENT_STATUS.md`; the historical FILE_CONTROL versions remain in Git history.

Canonical owners by mode:

| Owner | FILE_CONTROL (historical mode) | ISSUE_CONTROL (after verified merge) |
| --- | --- | --- |
| `AGENTS.md` | Durable rules, mode and approver policy | Same |
| Current task authorization | `CURRENT_TASK.md` on the authorized task ref | Explicitly selected, authenticated and **approved** `EXECUTION_SPEC_V1` GitHub Issue revision |
| Current progress/evidence | `CURRENT_STATUS.md` verified snapshot | Bounded Issue comments/receipts; PR/CI/GitHub host as live status truth |
| Documentation | `docs/README.md` and accepted contracts | Same |
| Source navigation | `docs/architecture/DOMAIN_MAP.md` | Same |

`ISSUE_APPROVERS` designates eligible GitHub actors; it is **not approval**. Each execution Issue must separately have an authentic `SPEC_APPROVAL_V1` comment from an authorized human approver matching repository, Issue number, `TASK_ID`, `SPEC_REVISION` and canonical `SPEC_SHA256`. An agent must not submit its own approval through a connected account or infer authorization from labels, Issue authorship or chat. Check the comment's verified author ID and revocations with the installed official helper. A successful structural digest without approval is non-executable.

Before state-changing work, resolve the **main-selected** mode, refresh task-relevant Git/PR/CI evidence, check workspace/writer ownership and the corresponding authorization owner. In FILE_CONTROL, read `CURRENT_TASK.md` and `CURRENT_STATUS.md`; in ISSUE_CONTROL, fetch the selected Issue and its exact approval via authenticated `gh`/connector, and do **not** treat legacy Task/Status files as current authority.

Chat history, Memory, handoff cards, audit replies, historical reports, old PRs, and archived documents are supporting evidence only. An agent-handoff card transmits authority references, not a second contract. Never use a GitHub Issue comment or progress label to expand an approved spec.

**Migration provenance:** [Issue #197](https://github.com/Lost0rz/FloatTabs/issues/197) and [carry-forward #198](https://github.com/Lost0rz/FloatTabs/issues/198) contain digest-bound approvals; [PR #199](https://github.com/Lost0rz/FloatTabs/pull/199) is the control-mode transition carrier. Actual cutover requires verified merge into `main`, approved Issue identities, host checks and safe preservation of independent product work. Never overwrite PR #195's local unique files or infer human product acceptance from Issue approval.

When consulting repository documentation beyond the mode-selected authority sources, read `docs/README.md` before relying on old architecture/product/design/validation/plan files. A historical document does not regain current Authority because its body says `FROZEN`, `LOCKED`, `canonical`, `accepted`, `implemented`, `current`, or `CONSTRUCTION_GATE_READY`.

If the user says “continue” and the active task is still accurate, continue it. Do not generate a second execution contract.

A materially new objective, scope, Authority, acceptance rule, STOP condition, or workspace owner requires task reconciliation before mutation.

## Repository identity

Distinguish:

- **Repository HEAD** — literal current commit;
- **Delivery / Semantic HEAD** — implementation identity being verified.

Under historical FILE_CONTROL, a commit changing only `CURRENT_STATUS.md` / `CURRENT_TASK.md` is `CONTROL_ONLY_DRIFT`; it does not invalidate unchanged product implementation evidence. In ISSUE_CONTROL, progress belongs in the approved Issue's receipt comments, not recreated root control files.

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

1. read authoritative `main` `AGENTS.md` to determine the **one** effective control mode;
2. in FILE_CONTROL, read the selected task ref's `CURRENT_TASK.md` and verified `CURRENT_STATUS.md`; in ISSUE_CONTROL, fetch the **exact selected Issue**, current revision/digest and authentic trusted approval comment;
3. refresh task-relevant source/ref/PR/CI evidence and writer/worktree state;
4. stop for missing authorization, conflicts, unsafe overlap or unknown unique work.

A truly new task must be authorized in the mode-selected owner **before** mutation. Several approved disjoint Issues may coexist; this is not a global single-active-task mutex.

### Phase / design execution gate

For a multi-phase architecture or other high-risk program governed by an accepted design/architecture contract, do not jump from the high-level phase description directly into product mutation.

Before each implementation phase:

1. reread the active contract plus the authority owner selected by the effective control mode;
2. perform a focused read-only audit of the exact production owners, call paths, lifecycle/retain boundaries, existing tests, and fresh repository evidence relevant to that phase;
3. freeze the phase's concrete scope, expected files/symbols, verification matrix, acceptance criteria, and STOP conditions in repository Authority when they materially change the task;
4. only then issue a concise execution card for the local executor;
5. keep the execution card bounded and avoid duplicating the full repository contract.

After implementation, run the phase-local machine verification required by the active program contract before merge/closeout. A chat plan or execution card never overrides an accepted repository contract or the mode-selected execution authority.

When a currently authorized phase contract provides an architecture-first sequence, follow its frozen local and CI gates and explicit human acceptance timing. Do not promote superseded phase plans into current permission or universal test cadence.

Use phase-local verification. A structural phase should prove the ownership/lifecycle primitive, data safety, regressions and machine-observable behavior needed for that phase. Do not make later policy/tuning-scale benchmarks blocking merely because they are measurable; defer them to the phase that actually uses those measurements unless the current accepted contract says the earlier decision depends on them.

### During

Do not expand the task for adjacent issues. In FILE_CONTROL record bounded material Follow-ups in `CURRENT_STATUS.md`; in ISSUE_CONTROL use Issue comments or a separately approved Issue as appropriate. Follow-ups never become executable without mode-selected authorization.

If implementation introduces or changes canonical ownership, writers, shared behavior, module boundaries, or a materially new responsibility, re-check the code-structure boundary before continuing.

### Completion

Every terminal task must run a Control Alignment Gate before successful handoff:

- obtain fresh outcome and host evidence;
- in FILE_CONTROL reread STATUS/TASK and change only materially stale owned facts;
- in ISSUE_CONTROL verify the selected approved Issue identity and update bounded Issue receipts/comments when needed; **do not recreate STATUS/TASK or open a control-only PR for progress**;
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

Real macOS interaction/runtime changes require relevant runtime acceptance before the owning program or release is finally accepted; static review alone is insufficient. A current accepted multi-phase contract may deliberately defer that human runtime/UI acceptance across intermediate architecture phases so the user tests the final integrated architecture once rather than repeatedly testing temporary intermediate states.

A current accepted multi-phase product contract may defer timing-sensitive real-product interaction acceptance to its integrated final gate. Local AI-driven evidence never substitutes for an explicitly required human UI acceptance verdict.

When the user explicitly chooses a reference-derived default for a performance policy, empirical tuning benchmarks may be deferred to a later tuning pass. That deferral does **not** waive code correctness, data-safety boundaries, or repository-required CI unless the user separately changes those gates. Record the chosen default as a product assumption rather than as measured truth.

Before merge/release, separately confirm current PR base/head, exact diff, required CI, reviews/mergeability, task scope, Authority integrity, and the acceptance gates applicable **at that boundary**. Repository-host gates apply to the literal identity GitHub governs and cannot be inferred from older semantic evidence.

## CI execution

FloatTabs macOS CI is intended to execute on the user's local Apple Silicon self-hosted runner while GitHub Actions provides scheduling and status. Required macOS jobs should target the established labels:

`[self-hosted, macOS, ARM64, mac-mini-ci]`

Do not silently switch required CI back to a GitHub-hosted `macos-*` runner unless the active task explicitly authorizes that fallback.

Because `pull_request` workflows do not run while the PR has a merge conflict, a task waiting on required PR CI must first ensure the PR is mergeable against the current base. Treat `workflow runs = 0` together with a conflicting PR as a trigger-layer problem, not as evidence that the self-hosted runner is offline.

For this public repository, self-hosted CI must not execute untrusted fork PR code by default. Gate self-hosted PR jobs to same-repository heads unless a separately reviewed security policy authorizes broader execution.

## Product-data safety

Browser Profiles, Web App Slot configuration, persisted website/session data, preferences, backups, and recovery material are user/product data.

Do not delete/reset them or replace unreadable persisted configuration with an empty fallback merely to recover runtime behavior unless the active task explicitly authorizes that behavior and its data-loss implications.

## Stop conditions

STOP and report evidence when:

- mode-selected execution authorization is missing, unapproved or materially stale;
- the requested mutation is outside task scope;
- task-relevant baseline/Authority changed materially;
- an overlapping predecessor contains unclassified unique work or unverified writer ownership;
- a required live repository-host gate fails;
- a linked design/plan change invalidates task acceptance or scope;
- safe ownership cannot be established without further navigation/incident evidence;
- a mode switch, untrusted approval, Issue digest mismatch or stale approval attempts to bypass cutover gates.

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
Control mode: <FILE_CONTROL / ISSUE_CONTROL>
Authority: <Task/Status ref OR approved repository/Issue/revision/digest>
Control alignment: <FILE_CONTROL STATUS/TASK OR ISSUE_CONTROL receipt/approval state>
PR / workspace: <state or N/A>
Final state: <short result>
```

Only report Skills actually used. If no merge occurred, say `NOT MERGED`; if no files changed, say `NONE`. In FILE_CONTROL, report stale STATUS/TASK when materially relevant; in ISSUE_CONTROL, report Issue revision, digest, approval and comment receipt evidence instead. For unresolved runtime failures, keep `Root cause: UNKNOWN`.

The receipt is status visibility only; it never becomes repository Authority.