# FloatTabs Agent Instructions

Before changing production behavior, read [README.md](README.md), the current
design/product contracts relevant to the task, and the relevant current release or
validation record. Documents explicitly marked Historical or Superseded must not
override current production behavior.

## Project policy

1. Preserve FloatTabs as a native macOS shell for persistent Web App Slots; do not
   silently turn a bounded runtime fix into a broader browser/product redesign.
2. Keep this file limited to durable project rules. Current PR, branch, HEAD,
   incident, release candidate, and active-task status belong in Git/PR/runtime
   evidence or a dedicated state record, not in AGENTS.md.
3. Existing persistent configuration, Browser Profile identity/session isolation,
   and user website data are product data. Do not delete/reset them or replace an
   unreadable configuration with an empty fallback merely to recover a runtime.

## Runtime / diagnostic evidence

4. Symptom recovery, reload success, slot reset success, app restart success, or a
   watchdog recovery does not by itself prove the underlying root cause.
5. Keep these conclusions distinct:
   - observation/diagnostic evidence;
   - recovery behavior;
   - causal root-cause evidence;
   - experimental mitigation;
   - production fix.
6. A diagnostic PR is not a production fix unless its production behavior is
   explicitly authorized and validated as such.
7. For an incident, bind evidence to the relevant identities when available:
   source HEAD/build, PR/branch, Slot identity, navigation/document generation or
   epoch, incident/session identifier, and the runtime timestamps needed to order
   events. Do not combine evidence from different identities as if it were one run.
8. Stale callbacks, probes, or events from an earlier navigation/runtime generation
   must not be treated as evidence about a later generation without explicit
   correlation.
9. Separate verified facts, plausible mechanisms, and uninspected areas. Unknown
   must remain unknown.

## Change discipline

10. Do not stack a new speculative fix on unresolved diagnostic/recovery branches
    without first reconciling what each open change proves, what it does not prove,
    and which behavior is intended for production.
11. During a controlled incident capture, do not rebuild, reinstall, replace the
    running app, reset persistent state, or materially change diagnostics unless
    the capture plan explicitly authorizes that mutation.
12. Preserve Slot-scoped ownership and lifecycle semantics. A fix for one Slot,
    navigation generation, fullscreen lifecycle, attention state, profile, or
    recovery path must not silently broaden ownership across unrelated Slots.
13. Current design/product contracts override older stage records. Historical
    validation is evidence about that historical build, not automatic proof for the
    current runtime.

## Validation

14. Validate the changed boundary with the smallest sufficient evidence. Use
    focused tests first; run broader regression when the affected lifecycle,
    persistence, WebKit behavior, or requested acceptance criteria justify it.
15. Tests and logs should establish behavioral contracts and causal boundaries,
    not merely increase coverage volume.
16. Before recommending merge or release, state unresolved root-cause uncertainty,
    untested runtime paths, and whether the change is diagnostic, recovery-only,
    experimental, or production-ready.
