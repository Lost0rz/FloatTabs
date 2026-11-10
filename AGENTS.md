# FloatTabs Agent Instructions

FloatTabs is a native macOS browser container. Engineering priority:
**user experience / stability → runtime correctness → diagnosability → governance**.
Do not expand governance, telemetry, or generic frameworks ahead of product needs.

CONTROL_MODE: ISSUE_CONTROL
ISSUE_APPROVERS: Lost0rz
ISSUE_DELEGATED_APPROVAL: ENABLED
ISSUE_WEB_SPEC_AUTHORING: ENABLED

## Project-specific authority boundaries

The installed Engineering Governance plugin is the sole owner of reusable engineering workflow. FloatTabs owns only its control-mode/approver opt-ins, product contracts, Domain boundaries, Runtime evidence needs, CI environment and data-safety policy. Do not copy generic approval, handoff, audit, Git/PR/worktree or verification procedures into this file; plugin updates must not require repeating those procedures in FloatTabs.

Real macOS runtime, installed app, TCC, multi-display and interaction claims require evidence from the actual Mac. Remote repository inspection alone cannot prove local behavior. Historical `CURRENT_TASK.md` and `CURRENT_STATUS.md` files are not active project controls.

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

## CI execution

FloatTabs macOS CI is intended to execute on the user's local Apple Silicon self-hosted runner while GitHub Actions provides scheduling and status. Required macOS jobs should target the established labels:

`[self-hosted, macOS, ARM64, mac-mini-ci]`

Do not silently switch required CI back to a GitHub-hosted `macos-*` runner unless the active task explicitly authorizes that fallback.

Because `pull_request` workflows do not run while the PR has a merge conflict, a task waiting on required PR CI must first ensure the PR is mergeable against the current base. Treat `workflow runs = 0` together with a conflicting PR as a trigger-layer problem, not as evidence that the self-hosted runner is offline.

For this public repository, self-hosted CI must not execute untrusted fork PR code by default. Gate self-hosted PR jobs to same-repository heads unless a separately reviewed security policy authorizes broader execution.

## Product-data safety

Browser Profiles, Web App Slot configuration, persisted website/session data, preferences, backups, and recovery material are user/product data.

Do not delete/reset them or replace unreadable persisted configuration with an empty fallback merely to recover runtime behavior unless the active task explicitly authorizes that behavior and its data-loss implications.
