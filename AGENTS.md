# FloatTabs Agent Instructions

FloatTabs is a native macOS browser container. Engineering priority:
**user experience / stability → runtime correctness → diagnosability → governance**.
Do not expand governance, telemetry, or generic frameworks ahead of product needs.

CONTROL_MODE: ISSUE_CONTROL
ISSUE_APPROVERS: Lost0rz
ISSUE_DELEGATED_APPROVAL: ENABLED

## Project authority and execution environments

Engineering Governance owns reusable task authorization, Issue approval verification, Skill routing, handoff, verification cadence, and Git/PR/worktree lifecycle. This file owns FloatTabs-specific product, documentation, CI, runtime, and data-safety constraints.

Cloud and local are execution/evidence contexts, not fixed planning, implementation, or review roles. Do not require a particular assistant, model, CLI, or worker technology. Actual actions depend on current capabilities, permissions, approved task scope, and fresh host/workspace evidence. Local runtime, installed app, TCC and interaction claims require local evidence; a remote repository observation alone is insufficient.

The declarations above select Issue Control and delegated-approval opt-in; they do not authorize self-approval or source/PR/merge actions. The selected approved Issue revision remains the execution authority under the installed Engineering Governance contract. Historical `CURRENT_TASK.md`/`CURRENT_STATUS.md` are not active task controls.

## Documentation authority

Consult `docs/README.md` before using historical plans/architecture/design/validation files. Use `docs/architecture/DOMAIN_MAP.md` for source/domain navigation. Stage-numbered plans, dated audits, old release records and archived documents are historical evidence by default, not a parallel active authority. An applicable current product contract retains its bounded authority; do not promote historical claims into current runtime facts.

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

## Project-specific verification and acceptance

- Validate affected `WKWebView` lifecycle/navigation, observer cleanup, runtime recovery, window/fullscreen, focus/event monitoring, persistence/migration and canonical-writer boundaries with evidence appropriate to the risk. Routine changes do not by default demand all test suites.
- Real macOS interaction/runtime acceptance is human-owned where the applicable product contract requires it. Deterministic browser automation, including Playwright, remains permitted, but AI-driven clicks/screenshots cannot replace required human UI acceptance.
- An accepted multi-phase contract may defer human interaction acceptance to its final integrated gate; intermediate implementation still needs the phase's scoped machine validation and data-safety evidence.
- A reference-derived performance default is a product assumption rather than an empirical result; defer tuning measurements only when the accepted contract permits it. Do not waive correctness, data-safety or required CI gates.

## CI execution

FloatTabs macOS CI is intended to execute on the user's local Apple Silicon self-hosted runner while GitHub Actions provides scheduling and status. Required macOS jobs should target the established labels:

`[self-hosted, macOS, ARM64, mac-mini-ci]`

Do not silently switch required CI back to a GitHub-hosted `macos-*` runner unless the active task explicitly authorizes that fallback.

Because `pull_request` workflows do not run while the PR has a merge conflict, a task waiting on required PR CI must first ensure the PR is mergeable against the current base. Treat `workflow runs = 0` together with a conflicting PR as a trigger-layer problem, not as evidence that the self-hosted runner is offline.

For this public repository, self-hosted CI must not execute untrusted fork PR code by default. Gate self-hosted PR jobs to same-repository heads unless a separately reviewed security policy authorizes broader execution.

## Product-data safety

Browser Profiles, Web App Slot configuration, persisted website/session data, preferences, backups, and recovery material are user/product data.

Do not delete/reset them or replace unreadable persisted configuration with an empty fallback merely to recover runtime behavior unless the active task explicitly authorizes that behavior and its data-loss implications.
