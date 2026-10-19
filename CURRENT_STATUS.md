# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE — RELEASE PREP**
Active task: `FT-RELEASE-V0.5.5-001` on `release/ft-v0.5.5`.

## Accepted product baseline

- PR #138 merged to protected `main` at `1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`.
- Post-merge main macOS CI run `39227623989`: PASS.
- Merged diagnostics preserve bounded cross-world liveness, event-loop/frame responsiveness evidence, Web-process epoch/termination correlation, and host-memory evidence.
- Root cause remains `UNKNOWN`; no recovery behavior was added and the stall is not claimed fixed.
- Latest public release before this task: `v0.5.4` / Build 22.

## Release target

```text
VERSION=0.5.5
BUILD=23
CHANNEL=public GitHub Release
ARCH=arm64
PURPOSE=long-term Air observation
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
```

The release preparation is metadata/documentation/package-only. No product runtime semantic change is authorized after the accepted main baseline.

## Observation expectations

Air is the long-term real-use observation machine. Sampling remains low-frequency and content-free. Short transient slowdowns may occur entirely between 30-second samples; the diagnostics provide trend/incident evidence, not proof that every interaction was responsive.

If a fresh slow/stall incident occurs on Air, preserve/export diagnostics before reload/restart when practical. Fresh incident evidence remains necessary for later causal investigation.

## Data safety

This release task must not modify or reset Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or existing diagnostic history.

## Next

Bump release metadata to v0.5.5 / Build 23, add matching release notes, open a release PR, require exact-head CI/QA PASS, merge through protected main, then verify the repository Publish Release workflow and public assets.
