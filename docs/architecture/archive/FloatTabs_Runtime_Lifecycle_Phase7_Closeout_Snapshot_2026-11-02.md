# FloatTabs Runtime Lifecycle — Phase 7 Closeout Snapshot

**Status:** `ARCHIVE / HISTORICAL EVIDENCE ONLY`  
**Captured:** `2026-11-02`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Delivered main:** `2b414982710b3f042fc7d6e9c88eb2d7117b4e38`  
**Purpose:** preserve the Phase 7/V5 closeout state before V6/Phase 8 supersedes the fixed-count policy.

This archive is intentionally not current task or product-policy authority. Read `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `docs/README.md`, and the current V6 contract first.

## Frozen historical references

- V5 program contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`
  - blob at Phase 8 design baseline: `5ca019005a78ac2432347284d5665801496ed0a5`
- Phase 7 implementation contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`
  - blob at Phase 8 design baseline: `88a3da38a0e3c1c99a724a1a5011817b5a519f29`
- Phase 7 semantic/Real-Mac acceptance head: `b894641a254e7ffb49c84b4ed32d9c70a3f28ad7`
- Phase 7 final PR head: `d8149390eb2d991df529a23dc77e74fd41c4a852`
- Phase 7 merge commit / Phase 8 design baseline: `2b414982710b3f042fc7d6e9c88eb2d7117b4e38`

## Delivered Phase 7 behavior

The merged implementation established:

```text
Automatic / Keep Loaded product model
Slot/Profile/session lifetime separated from Runtime lifetime
SlotLifecycleCoordinator = sole lifecycle writer
WebViewPool = Runtime hibernate/restore mechanism owner
Phase 6 restore preserved
Generating = hard Runtime protection
Ready/unread = no Runtime-residency requirement
Keep Loaded = no hidden Hot host and no launch preload
Runtime reclaim = no Browser Profile/session/cache deletion side effect
```

The merged Phase 7 policy values were:

```text
normal Automatic resident target = 2
Automatic inactive grace = 30 seconds
warning Automatic target = 1
critical Automatic target = 0
```

These values were accepted as Phase 7 engineering defaults and passed machine + bounded Real-Mac acceptance. They are preserved here as historical delivered evidence.

## Why the policy is superseded

Post-merge product review identified that `normal target = 2` behaves as a hard normal resident-count ceiling: opening a third eligible Automatic Runtime can force immediate reclaim even when the Mac still has healthy memory headroom.

The user clarified the intended product model:

- user configures an approximate memory budget, not a maximum live-page count;
- several pages may remain resident while FloatTabs/WebKit is under budget;
- when budget or system pressure requires reclaim, inactive Runtime should be released progressively;
- active/generating/protected work remains protected;
- Phase 1-7 hibernate/restore/session/notification foundations remain valid.

V6/Phase 8 therefore supersedes only the fixed-count / unconditional normal-release policy. It does **not** invalidate the structural Phase 1-7 delivery.

## Historical Real-Mac evidence

Phase 7 acceptance established that Runtime reclaim materially reduces aggregate resource use without destructive session cleanup. The evidence was intentionally aggregate only; no exact per-Slot WebContent memory attribution was claimed.

This evidence remains useful for proving the value of hibernate/reclaim, but the Phase 7 acceptance criterion “converge to fixed resident count” is not a valid Phase 8 target.

## Routing

Current design authority after this snapshot:

```text
FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md
→ FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md
```

Do not use V5/Phase 7 fixed counts as current implementation goals once Phase 8 construction begins.
