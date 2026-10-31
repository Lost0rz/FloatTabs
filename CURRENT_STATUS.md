# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT MULTI-RUNTIME PRESSURE INVESTIGATION**

Current task: `FT-JSC-MULTI-RUNTIME-002` — `ACTIVE / AIR_SOAK_READY`.

PR #161 is closed `ARCHIVE-ONLY / UNMERGED`. Its watchdog `2s -> 5s` experiment reduced periodic work but did not eliminate WebContent crashes and is not production state.

## Canonical / active state

```text
MAIN=26c81d83d3bdd771e98e355337b78622e2b25b17
ACTIVE_BRANCH=codex/ft-jsc-multi-runtime-002
ACTIVE_PR=#162 OPEN / DRAFT / UNMERGED
IMPLEMENTATION_COMMIT=3dff7e90d23918e69e12d2820ce6c1be31805e99
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
```

The prior exact-head Air-soak artifact used for the diagnostic baseline was:

```text
SOAK_SOURCE_REVISION=ca46c3fad6bb7c7c106fb8cbbdf7fbde89da3120
SOAK_SOURCE_REVISION_EXACT=true
SOAK_DMG_SHA256=e67d277c6d0287d58f04566b094da8cffde6626e45588f02b754cc29f256339e
VERSION=0.5.8
BUILD=26
ARCH=arm64
```

## Confirmed historical native family

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
COMMON_FAULT_ADDRESS=0x48
COMMON_FAULT_SYMBOL=llint_entry_osr_function_for_call+120
ASYNC_PATH=async-generator / async-iterator / microtask
JSC_EXACT_TRIGGER=UNKNOWN
JSC_ROOT_CAUSE=UNKNOWN
```

## PR #162 diagnostic-only measurement result

PR #162 added read-only resident Attention counters:

```text
resident_attention_generating_count
resident_attention_ready_count
resident_attention_protected_count
```

No generation, Attention/Unread, residency, recovery, Browser Profile, session or user-data semantics were changed by that measurement step.

### Latest Air soak window

Uploaded runtime logs cover one continuous session:

```text
SESSION_ID=E5464F6C-550B-4792-A7A8-3035874D9266
UTC_WINDOW=2026-10-30T23:48:51Z -> 2026-10-31T01:38:30Z
SOURCE_REVISION=ca46c3fad6bb7c7c106fb8cbbdf7fbde89da3120
SOURCE_REVISION_EXACT=true
```

Three FloatTabs-recorded WebContent terminations occurred:

```text
01:21:15Z  slot FA6B82CF...  generating=true  attention_protected=true
            resident_generating=1  resident_ready=0  resident_protected=1

01:25:17Z  slot 1FA8BE8B...  generating=true  attention_protected=true
            resident_generating=2  resident_ready=0  resident_protected=2

01:25:41Z  slot 8F6BC8A6...  generating=true  attention_protected=true
            resident_generating=2  resident_ready=0  resident_protected=2
```

Interpretation:

```text
SINGLE_GENERATING_CRASH_REPRODUCED=YES
MULTI_GENERATING_REQUIRED_FOR_CRASH=NO
MULTI_GENERATING_CLUSTER_CORRELATION=SUPPORTED
JSC_ROOT_CAUSE=UNKNOWN
```

The second and third incidents were different Slots about 24 seconds apart. At the second incident two resident Slots were generating. After that Slot recovered/re-entered generation, the other still-generating Slot terminated about 24 seconds after the first clustered incident and about 7 seconds after dual generation resumed.

Across 107 roughly minute-scale performance checkpoints in the two uploaded logs:

```text
resident_generating=0 : 44 checkpoints
resident_generating=1 : 45 checkpoints
resident_generating=2 : 18 checkpoints
```

Two-generating state therefore appeared in about 17% of checkpoint samples but contained 2/3 observed terminations. This is a small-sample correlation only, not causal or a reliable crash-rate estimate.

No confirmed post-finish stall occurred in these two logs.

## Memory-pressure evidence and newly bounded intervention

The same Air session recorded seven app-level memory-pressure `warning` incidents on a 24 GiB host. Every warning evaluated five resident Slots and released none because current production logic intentionally classifies warning as `warning_no_eviction`.

At every warning there was at least one, and often two, resident Slots that already met the same safety boundary used by critical-pressure eviction except for pressure severity itself:

```text
residency=warm
inactive / not visible
existing pending inactive release plan
media_protected=false
attention_protected=false
```

Observed warning-time safe-candidate counts:

```text
00:23:12Z -> 2
00:27:52Z -> 1
00:50:05Z -> 2
00:57:13Z -> 2
00:59:57Z -> 1
01:18:31Z -> 2
01:21:25Z -> 2
```

Baseline code behavior before the corrective was explicit:

```text
memory pressure WARNING  -> diagnostics only; no eviction
memory pressure CRITICAL -> evict eligible inactive warm unprotected runtimes
```

The soak therefore establishes a bounded product-owned pressure gap: FloatTabs receives repeated OS memory warnings while keeping inactive Warm runtimes resident even when they are already scheduled for release and have no visibility/media/Attention protection.

This does **not** prove memory pressure is the JSC root cause. It does establish one safe single-variable mitigation opportunity that can lower nonessential long-lived WebContent residency without touching active or protected work.

## Current decision

```text
ACTIVE_TASK=FT-JSC-MULTI-RUNTIME-002
ACTIVE_PR=#162 OPEN / DRAFT / UNMERGED
AIR_SOAK_DIAGNOSTIC_GATE=COMPLETED
SAFE_BOUNDED_INTERVENTION=WARNING_PRESSURE_EARLY_WARM_RELEASE
INTERVENTION_AUTHORIZED=YES
INTERVENTION_IMPLEMENTED=YES
IMPLEMENTATION_COMMIT=3dff7e90d23918e69e12d2820ce6c1be31805e99
TARGET=existing inactive Warm pending-release runtimes only
ACTIVE_OR_VISIBLE_RELEASE=FORBIDDEN
ATTENTION_OR_MEDIA_PROTECTED_RELEASE=FORBIDDEN
HOT_RUNTIME_RELEASE=FORBIDDEN
PROFILE_SESSION_USER_DATA_MUTATION=FORBIDDEN
JSC_ROOT_CAUSE=UNKNOWN
PRODUCTION_RELEASE=NOT_AUTHORIZED
```

The single corrective is implemented through the existing lifecycle release path. Warning pressure now releases only eligible inactive Warm pending-release runtimes; active/visible, Hot, media-protected and Attention-protected runtimes remain protected. Focused and full XCTest, Debug/Release arm64 builds, exact-head CI/QA, and a fresh exact-head local QA DMG have passed.

Next gate: Air-side soak using the fresh exact-head QA DMG. Do not interpret the intervention as proof of JSC root cause.

## Separate product follow-up

Active-visible ChatGPT completion currently intentionally suppresses persistent unread/red-dot state. That is a separate product-semantic task and remains out of scope for `FT-JSC-MULTI-RUNTIME-002`.
