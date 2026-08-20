# FloatTabs v0.1.3 Monterey Compatibility

Release date: pending real-Monterey acceptance

This is a **separate Monterey Compatibility Edition** based on the accepted FloatTabs v0.1.3 Build 5 product baseline. It is not the standard v0.1.3 package and is not a unified macOS 12/macOS 13+ build.

## Release-line isolation

- Standard edition: `v0.1.3`, unchanged, normal macOS 13+ package.
- Compatibility edition: `v0.1.3-monterey`, built only from `release/v013-monterey-compat`.
- The compatibility branch is not merged into `main`.
- Compatibility source changes are applied only at build time; committed standard `FloatTabs/**` source remains untouched.
- The compatibility publisher is triggered only by the exact `v0.1.3-monterey` tag.
- The standard `v0.1.3` tag and Release are never replaced, refreshed, or repackaged by this workflow.

## Compatibility target

- Intended for **macOS Monterey 12.7.6** and later Monterey 12.x systems.
- Binary deployment target: `MACOSX_DEPLOYMENT_TARGET=12.0`.
- Universal 2 package: Apple Silicon `arm64` + Intel `x86_64`.
- Application version remains **Version 0.1.3 (Build 5)**.
- Distribution artifact: `FloatTabs-0.1.3-monterey.dmg`.

## Monterey-specific runtime behavior

The Compatibility Edition intentionally uses Monterey-specific runtime behavior rather than embedding the standard macOS 13+ runtime as a second path.

Current hardening includes:

- minimal WKWebView construction on Monterey;
- no BrowserVersion/private user-agent probing during initial WebView creation;
- no preferred-content-mode override during initial WebView creation;
- no injected hidden-scrollbar policy during initial WebView creation;
- no traversal/mutation of WebKit internal AppKit scroll views;
- deferred saved-WebView restoration to avoid startup crash loops;
- typed URLs are persisted only after WebKit commits navigation;
- provisional URL KVO is not used as the Monterey durability boundary;
- element fullscreen / FloatTabs fullscreen ownership handling is intentionally disabled for this compatibility release candidate;
- stage-only runtime breadcrumbs and exact dSYM artifacts are retained for crash diagnosis.

The standard v0.1.3 package keeps its existing accepted macOS 13+ behavior and is not modified by these compatibility decisions.

## Validation contract

Compatibility CI must pass:

- release-line isolation allowlist check;
- deterministic Monterey source preparation;
- assertions that standard runtime branches do not leak into the compatibility build path;
- Debug build with macOS 12.0 deployment target;
- XCTest with macOS 12.0 deployment target;
- Universal 2 Release build;
- `arm64` and `x86_64` verification;
- Mach-O `LC_BUILD_VERSION` minimum OS verification;
- `LSMinimumSystemVersion` verification;
- DMG verification;
- DMG and dSYM SHA-256 verification.

CI compile/link/package success is **not** sufficient for release approval because GitHub-hosted runners do not exercise the application on a real Monterey 12.7.6 host.

## Required real macOS 12.7.6 acceptance

Do not create the `v0.1.3-monterey` tag or Release until all of the following pass on a real Monterey machine:

1. Launch with an existing saved Profile and keep the process alive.
2. Present FloatTabs and load the saved Web App.
3. Add another Web App and load a page.
4. Enter a new address and press Return without a crash.
5. Quit and relaunch with the saved active Profile.
6. Switch Tabs and reload.
7. Confirm ordinary non-fullscreen use is stable; fullscreen is intentionally out of scope for this Compatibility Edition candidate.

## Assets

- `FloatTabs-0.1.3-monterey.dmg`
- `FloatTabs-0.1.3-monterey.dmg.sha256`
- `FloatTabs-0.1.3-monterey.dSYM.zip`
- `FloatTabs-0.1.3-monterey.dSYM.zip.sha256`
