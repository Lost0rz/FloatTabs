# FloatTabs Agent Instructions

This repository uses three control-plane files. Before changing code, diagnostics,
tests, build configuration, release state, or project documentation, read them in
this order:

1. `AGENTS.md` — durable project rules.
2. `CURRENT_STATUS.md` — authoritative current repository / PR / worktree state.
3. `CURRENT_TASK.md` — the single currently authorized task and its boundaries.

If the local checkout, branch, HEAD, worktree path, PR state, or task does not match
`CURRENT_STATUS.md` / `CURRENT_TASK.md`, stop. Do not silently substitute another
checkout or continue from memory, chat history, an older handoff, or an old PR.

## Authority model

- `AGENTS.md` contains durable engineering policy only. Do not put transient
  branch, HEAD, PR, incident, or release values here.
- `CURRENT_STATUS.md` is the repository's current-state authority. Update it when
  main HEAD, active PR, authorized worktree, incident classification, release
  candidate, or other material project state changes.
- `CURRENT_TASK.md` defines the only active task. Work outside its scope requires
  an explicit task-state update first.
- Chat history, Memory, issue comments, historical reports, and superseded stage
  documents are supporting evidence; they do not override these files.
- A missing or stale control-plane file is a blocker, not permission to guess.

## Project policy

1. Preserve FloatTabs as a native macOS shell for persistent Web App Slots; do not
   silently turn a bounded runtime fix into a broader browser/product redesign.
2. Existing persistent configuration, Browser Profile identity/session isolation,
   and user website data are product data. Do not delete/reset them or replace an
   unreadable configuration with an empty fallback merely to recover a runtime.
3. One local worktree must be explicitly authorized in `CURRENT_STATUS.md` before
   production changes. A different clean-looking checkout is not an acceptable
   substitute.
4. Before starting a new branch or PR, reconcile related open PRs/worktrees and
   record whether each is ACTIVE, FROZEN, MERGED, SUPERSEDED, ABANDONED, or
   SEPARATE_SCOPE.

## Runtime / diagnostic evidence

5. Symptom recovery, reload success, slot reset success, app restart success, or a
   watchdog recovery does not by itself prove the underlying root cause.
6. Keep these conclusions distinct:
   - observation / diagnostic evidence;
   - recovery behavior;
   - causal root-cause evidence;
   - experimental mitigation;
   - production fix.
7. A diagnostic PR is not a production fix unless its production behavior is
   explicitly authorized and validated as such.
8. For an incident, bind evidence to the relevant identities when available:
   source HEAD/build, PR/branch, Slot identity, navigation/document generation or
   epoch, incident/session identifier, and the runtime timestamps needed to order
   events. Do not combine evidence from different identities as if it were one run.
9. Stale callbacks, probes, or events from an earlier navigation/runtime generation
   must not be treated as evidence about a later generation without explicit
   correlation.
10. Separate verified facts, plausible mechanisms, and uninspected areas. Unknown
    must remain unknown.

## Change discipline

11. Do not stack a new speculative fix on unresolved diagnostic/recovery branches
    without first reconciling what each open change proves, what it does not prove,
    and which behavior is intended for production.
12. During a controlled incident capture, do not rebuild, reinstall, replace the
    running app, reset persistent state, or materially change diagnostics unless
    `CURRENT_TASK.md` explicitly authorizes that mutation.
13. Preserve Slot-scoped ownership and lifecycle semantics. A fix for one Slot,
    navigation generation, fullscreen lifecycle, attention state, profile, or
    recovery path must not silently broaden ownership across unrelated Slots.
14. Current design/product contracts override older stage records. Historical
    validation is evidence about that historical build, not automatic proof for the
    current runtime.
15. State-governance work must remain docs/control-plane only unless
    `CURRENT_TASK.md` explicitly changes scope.

## Validation and handoff

16. Validate the changed boundary with the smallest sufficient evidence. Use
    focused tests first; run broader regression when the affected lifecycle,
    persistence, WebKit behavior, or requested acceptance criteria justify it.
17. Tests and logs should establish behavioral contracts and causal boundaries,
    not merely increase coverage volume.
18. Before recommending merge or release, state unresolved root-cause uncertainty,
    untested runtime paths, and whether the change is diagnostic, recovery-only,
    experimental, or production-ready.
19. A handoff is complete only when another agent can read the three control-plane
    files, verify the checkout against them, and continue without reconstructing
    current state from chat history.
