# FloatTabs Agent Instructions

This repository uses three control-plane files. Before changing code, diagnostics,
tests, build configuration, release state, or project documentation, read them in
this order:

1. `AGENTS.md` — durable project rules.
2. `CURRENT_STATUS.md` — the current state contract.
3. `CURRENT_TASK.md` — the single currently authorized task and its boundaries.

If the local checkout, branch, HEAD, authorized worktree identity, PR state, or
task does not match the control-plane files after a fresh remote ref check, STOP.
The locally resolved absolute path must uniquely satisfy that worktree identity;
it is local evidence, not a committed repository value. Do not silently substitute
another checkout or continue from chat history, Memory, an older handoff, or an
old PR.

## Authority model

- `AGENTS.md` contains durable engineering policy only. Do not put transient
  branch, HEAD, PR, incident, or release values here.
- `CURRENT_STATUS.md` defines intended project state, classifications, and
  authorization. Git/GitHub refs remain authoritative for the actual SHA currently
  stored at a branch or PR head.
- `CURRENT_TASK.md` defines the only active task. Work outside its scope requires
  an explicit task-state update first.
- If a live Git/GitHub ref differs from `CURRENT_STATUS.md`, the state contract is
  stale. Stop and reconcile the state file before implementation work.
- Chat history, Memory, issue comments, historical reports, and superseded stage
  documents are supporting evidence; they do not override these files.
- A missing or stale control-plane file is a blocker, not permission to guess.

## Session entry gate

Before implementation work:

1. refresh remote refs without modifying working files;
2. read the three control-plane files from the authorized branch;
3. verify repository identity, branch, HEAD, upstream, authorized worktree identity,
   locally resolved worktree path, and clean/dirty state against the control-plane
   contract;
4. verify the requested work fits `CURRENT_TASK.md`;
5. stop on any mismatch until the state contract is updated.

Read-only inventory is allowed when the current task explicitly authorizes it even
if no production worktree is yet authorized.

## Project policy

1. Preserve FloatTabs as a native macOS shell for persistent Web App Slots; do not
   silently turn a bounded runtime fix into a broader browser/product redesign.
2. Existing persistent configuration, Browser Profile identity/session isolation,
   and user website data are product data. Do not delete/reset them or replace an
   unreadable configuration with an empty fallback merely to recover a runtime.
3. Exactly one production worktree identity must be explicitly authorized in
   `CURRENT_STATUS.md` before production implementation changes. The repository
   records its logical identity/branch/ref contract; machine-specific absolute
   paths are resolved locally and must not be committed to this public repository.
   A different clean-looking checkout is not an acceptable substitute.
4. Before changing production behavior, read the current product/design contract
   relevant to the affected boundary plus the current release/validation record.
   Historical or superseded records are evidence only and must not override the
   current contract.
5. Before starting a new branch or PR, reconcile related open PRs/worktrees and
   record whether each is ACTIVE, FROZEN, MERGED, SUPERSEDED, ABANDONED, or
   SEPARATE_SCOPE.

## Runtime / diagnostic evidence

6. Symptom recovery, reload success, slot reset success, app restart success, or a
   watchdog recovery does not by itself prove the underlying root cause.
7. Keep these conclusions distinct:
   - observation / diagnostic evidence;
   - recovery behavior;
   - causal root-cause evidence;
   - experimental mitigation;
   - production fix.
8. A diagnostic PR is not a production fix unless its production behavior is
   explicitly authorized and validated as such.
9. For an incident, bind evidence to the relevant identities when available:
   source HEAD/build, PR/branch, Slot identity, navigation/document generation or
   epoch, incident/session identifier, and the runtime timestamps needed to order
   events. Do not combine evidence from different identities as if it were one run.
10. Stale callbacks, probes, or events from an earlier navigation/runtime generation
   must not be treated as evidence about a later generation without explicit
   correlation.
11. Separate verified facts, plausible mechanisms, and uninspected areas. Unknown
    must remain unknown.

## Change discipline

12. Do not stack a new speculative fix on unresolved diagnostic/recovery branches
    without first reconciling what each open change proves, what it does not prove,
    and which behavior is intended for production.
13. During a controlled incident capture, do not rebuild, reinstall, replace the
    running app, reset persistent state, or materially change diagnostics unless
    `CURRENT_TASK.md` explicitly authorizes that mutation.
14. Preserve Slot-scoped ownership and lifecycle semantics. A fix for one Slot,
    navigation generation, fullscreen lifecycle, attention state, profile, or
    recovery path must not silently broaden ownership across unrelated Slots.
15. Current design/product contracts override older stage records. Historical
    validation is evidence about that historical build, not automatic proof for the
    current runtime.
16. State-governance work must remain docs/control-plane only unless
    `CURRENT_TASK.md` explicitly changes scope.

## State transition discipline

17. When material state changes, update `CURRENT_STATUS.md` and
    `CURRENT_TASK.md` together when both are affected.
18. Do not hard-code the SHA of the commit that contains `CURRENT_STATUS.md`
    inside that same file. That creates an impossible self-reference. Instead,
    record immutable baselines and require the local HEAD to equal the freshly
    fetched remote head of the authorized branch.
19. A status transition is not complete until the updated control-plane files are
    committed/pushed and the live branch/PR metadata agrees with them.

## Validation and handoff

20. Validate the changed boundary with the smallest sufficient evidence. Use
    focused tests first; run broader regression when the affected lifecycle,
    persistence, WebKit behavior, or requested acceptance criteria justify it.
21. Tests and logs should establish behavioral contracts and causal boundaries,
    not merely increase coverage volume.
22. Before recommending merge or release, state unresolved root-cause uncertainty,
    untested runtime paths, and whether the change is diagnostic, recovery-only,
    experimental, or production-ready.
23. Required branch-protection checks must pass on the exact commit proposed for
    merge. If path filters prevent an automatic required check from running,
    explicitly dispatch the existing required workflow on that branch/head rather
    than treating an absent check as a pass.
24. A handoff is complete only when another agent can read the three control-plane
    files, verify the checkout against them, and continue without reconstructing
    current state from chat history.
