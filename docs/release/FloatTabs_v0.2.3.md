# FloatTabs v0.2.3

## Focused baseline

This release records the current interaction baseline for presenting FloatTabs
from another macOS application.

- The global summon shortcut presents and activates FloatTabs when another app
  owns focus.
- If FloatTabs already owns focus, the same shortcut keeps its normal hide
  behavior.
- The native key-window handoff is retried briefly because FloatTabs runs as a
  menu-bar accessory application.
- Once the active WebView is ready, its website adapter initializes the
  primary input focus automatically. This makes voice input and page
  navigation available immediately after summoning.
- The manual primary-focus shortcut remains available and cancels the pending
  automatic focus initialization when the user chooses a different target.

## Verification

- FloatTabs unit and integration tests passed.
- Release build completed for arm64 and x86_64.
- The local Release application was replaced and launched successfully.

This package is an unsigned QA build unless Developer ID signing and
notarization credentials are supplied to the release script.
