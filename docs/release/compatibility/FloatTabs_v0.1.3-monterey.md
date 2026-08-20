# FloatTabs v0.1.3 Monterey Compatibility

Release date: 2026-08-20

This is a compatibility build of **FloatTabs v0.1.3 Build 5** for Macs that cannot run macOS 13 or later.

## Compatibility target

- Intended for **macOS Monterey 12.7.6** and later Monterey 12.x systems.
- The binary is built with `MACOSX_DEPLOYMENT_TARGET=12.0`, so macOS 12.7.6 is within the supported binary deployment range.
- Universal 2 package: Apple Silicon `arm64` + Intel `x86_64`.
- The application version shown in Settings remains **Version 0.1.3 (Build 5)**.
- This compatibility Release is separate from the standard `v0.1.3` Release and does not replace it.

## Included v0.1.3 behavior

The compatibility package contains the same accepted Build 5 product behavior as the standard v0.1.3 package, including:

- first-click Tab / Add / Pin / Settings activation;
- collapsible Tab rail with Web-content width reclaim and the 12 pt movement gutter;
- synchronized fullscreen restoration and WebKit presentation teardown handling;
- Settings → About FloatTabs version/build/latest-fixes information;
- Hot / Warm / Cold WebView residency policies;
- Universal 2 Apple Silicon and Intel support.

## Compatibility validation contract

Before publishing, CI must pass all of the following with a macOS 12.0 deployment target:

- Debug build;
- XCTest build/run on the current CI runner while compiling all app/test code against macOS 12 availability constraints;
- Universal 2 Release build;
- `arm64` and `x86_64` architecture verification;
- Mach-O `LC_BUILD_VERSION` minimum OS verification;
- `LSMinimumSystemVersion` verification;
- DMG verification and SHA-256 checksum verification.

Because GitHub-hosted CI is not running the application on an actual Monterey 12.7.6 machine, this Release establishes compile/link/package compatibility for Monterey. A final real-Mac Monterey smoke test is still recommended for WebKit/runtime-specific behavior.

## Assets

- `FloatTabs-0.1.3-monterey.dmg`
- `FloatTabs-0.1.3-monterey.dmg.sha256`
- `FloatTabs-0.1.3-monterey.dSYM.zip`
- `FloatTabs-0.1.3-monterey.dSYM.zip.sha256`
