# FloatTabs Current Task

**Task ID:** `FT-JSC-MULTI-RUNTIME-002`
**Title:** Audit multi-generating long-lived ChatGPT WebContent clustering and shared resource pressure
**Status:** `ACTIVE / CORRECTIVE AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `RUNTIME STABILITY / EVIDENCE-DRIVEN CORRECTIVE`
**Authorized baseline:** `main@26c81d83d3bdd771e98e355337b78622e2b25b17`
**Active PR:** `#162` / `codex/ft-jsc-multi-runtime-002`
**JSC root cause:** `UNKNOWN`

## Purpose

Reduce one now-measured FloatTabs-owned WebContent residency pressure path without interrupting ChatGPT generation or weakening Attention/Unread protection, then produce a fresh exact-head QA DMG and repeat Air soak.

This task does not claim that memory pressure, concurrent generation, Attention protection, or FloatTabs is the proven JSC root cause.

## Evidence established by PR #162 Air soak

Exact soak artifact:

```text
SOURCE_REVISION=ca46c3fad6bb7c7c106fb8cbbdf7fbde89da3120
SOURCE_REVISION_EXACT=true
DMG_SHA256=e67d277c6d0287d58f04566b094da8cffde6626e45588f02b754cc29f256339e
SESSION_ID=E5464F6C-550B-4792-A7A8-3035874D9266
```

Observed WebContent terminations:

```text
01:21:15Z resident_generating=1 resident_protected=1
01:25:17Z resident_generating=2 resident_protected=2
01:25:41Z resident_generating=2 resident_protected=2
```

All three affected Slots were generating and Attention-protected. One crash occurred with only one generating resident Slot, therefore multi-generation is not required. Two different-Slot incidents clustered about 24 seconds apart while dual generation was present, so multi-generation remains a correlation, not a cause.

Across 107 minute-scale performance checkpoints:

```text
resident_generating=0 -> 44
resident_generating=1 -> 45
resident_generating=2 -> 18
```

The 2-generating state appeared in about 17% of checkpoint samples but contained 2/3 terminations. Treat this as small-sample correlation only.

### Memory-pressure evidence

Seven FloatTabs memory-pressure warnings were recorded in the same session. Each warning evaluated five resident Slots. Current code releases nothing at warning severity and records `warning_no_eviction`.

At every warning at least one resident Slot already satisfied the same safe lifecycle boundary used by critical-pressure Warm eviction except for severity:

```text
residency_policy=warm
pending inactive release plan exists
not visible / not active
media_protected=false
attention_protected=false
```

Safe-candidate counts by warning:

```text
00:23:12Z -> 2
00:27:52Z -> 1
00:50:05Z -> 2
00:57:13Z -> 2
00:59:57Z -> 1
01:18:31Z -> 2
01:21:25Z -> 2
```

Current source behavior:

```text
WARNING  -> evaluate/log only
CRITICAL -> evictInactiveWarmForMemoryPressure(...)
```

This establishes one bounded FloatTabs-owned mitigation opportunity. It does not establish memory as root cause.

## Authorized intervention — exactly one

Implement:

```text
WARNING_PRESSURE_EARLY_WARM_RELEASE
```

On an OS memory-pressure `warning`, FloatTabs may immediately release only a runtime that already satisfies **all** of these conditions:

```text
residencyPolicy == warm
inactive / not visible
existing inactive pending-release plan
WebView still resident
media protection == false
Attention protection == false
```

Use the existing lifecycle release path. The change should reuse the existing critical-pressure safety boundary rather than create a second release authority.

### Required semantics

- `warning` may accelerate release of a Warm runtime that is already scheduled to be released later.
- `critical` behavior must continue to work.
- Active or actually visible runtimes must never be released.
- ChatGPT `Generating` or `Ready` Attention-protected runtimes must never be released.
- Media-protected runtimes must never be released.
- `Hot` runtimes must not become warning-pressure eviction candidates in this task.
- Browser Profile, cookie/session, website data, Slot config, preferences, backup and recovery data must not be deleted or reset.
- Do not use reload/restart/reset as mitigation.
- Do not alter generation, Attention/Unread, stable response identity, RemoteOrbit focus, background-media semantics or active-visible completion red-dot behavior.

## Diagnostics requirement

Memory-pressure diagnostics must tell the truth after the behavior change.

For both warning and critical pressure, record per-Slot eligibility/decision consistently. A completed warning-driven release must not be mislabeled `critical_pressure_eligible`.

The exact diagnostic naming may be chosen during implementation, but must distinguish at least:

```text
pressure_level=warning | critical
release_eligible=true | false
release_reason=<warning or critical eligible / protection reason>
action=release_completed when release occurs
```

Do not add unrelated diagnostics.

## Verification gate

Before a new Air soak:

1. focused lifecycle/memory-pressure tests must cover:
   - warning releases inactive Warm pending-release unprotected runtime;
   - warning preserves active/visible runtime;
   - warning preserves Attention-protected Generating runtime;
   - warning preserves Attention-protected Ready runtime;
   - warning preserves media-protected runtime;
   - warning preserves Hot runtime;
   - critical pressure behavior still passes;
   - diagnostic reason/level for warning release is correct.
2. full required XCTest suite passes;
3. Debug arm64 build passes;
4. Release arm64 build passes;
5. branch is pushed to PR #162 and exact-head remote verified;
6. exact-head CI and QA build pass;
7. a local exact-head QA DMG is produced with:
   - exact source revision;
   - `FloatTabsSourceRevisionExact=true`;
   - arm64;
   - SHA256;
   - `hdiutil verify` PASS.

## Air soak comparison

The next Air soak must compare against the diagnostic baseline above and record:

```text
memory warning count
warning-driven Warm release count
resident_slot_count before/after warning when observable
resident_attention_generating_count at any termination
resident_attention_protected_count at any termination
WebContent termination count / timing
clustered different-Slot termination timing
confirmed post-finish stall count
```

Interpretation rules:

```text
FEWER_CRASHES != ROOT_CAUSE_PROVEN
WARNING_RELEASE_PRECEDES_LOWER_PRESSURE != MEMORY_ROOT_CAUSE_PROVEN
MULTI_GENERATING_CORRELATION != CONCURRENT_GENERATION_ROOT_CAUSE
NO_CRASH_DURING_BOUNDED_SOAK != FIX_PROVEN
```

## STOP conditions

STOP and report rather than broaden scope if:

- implementation requires releasing active, visible, Hot, media-protected or Attention-protected runtime;
- the only way forward requires Browser Profile/session/user-data mutation;
- implementation requires WebView/process-pool/data-store ownership redesign;
- tests/builds fail because of the intervention;
- new evidence contradicts the lifecycle safety boundary;
- a second speculative mitigation would be required.

## Completion boundary

This iteration reaches `AIR_SOAK_READY` only after the single warning-pressure Warm release intervention is implemented, verified, pushed to PR #162, and tied to a fresh exact-head QA DMG.

Production release is not authorized.

## Separate follow-up not authorized here

Active-visible ChatGPT completion currently suppresses persistent unread/red-dot state. That remains a separate product task and must not be mixed into this runtime corrective.
