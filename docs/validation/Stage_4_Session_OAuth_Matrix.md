# Stage 4 Session / OAuth Compatibility Matrix

> Status: ACCEPTED BASELINE
> Baseline commit: `8758cc587f9e74665126f3ebdcbf78c8e130bce5`
> Frozen app Bundle Identifier: `com.lost0rz.FloatTabs`
> Real-Mac acceptance date: 2026-08-09

## Purpose

This matrix records real website authentication and session behavior after the Stage 4 navigation/popup layer passed automated and Real-Mac acceptance.

The Stage 4C acceptance target is the session lifecycle itself: authenticated use, shared website data across persistent Slots, quit/relaunch restore, and restore after a rendering change that rebuilds the Slot WKWebView. A fresh provider OAuth flow may be recorded later as compatibility coverage; it is not used to invalidate an already-working persistent WebKit session profile.

## Required sequence per site

For each site that is tested in depth:

1. launch the current Stage 4 build;
2. open or create the site's persistent FloatTabs Slot;
3. confirm normal authenticated use;
4. quit FloatTabs completely with `Cmd+Q` or the menu-bar Quit action;
5. relaunch FloatTabs and confirm the site is still authenticated;
6. change **Browser Identity** or **Website Mode** once so that the Slot's WKWebView is rebuilt;
7. confirm the same authenticated website session is still available after the rebuild;
8. record any provider warning, blocked embedded login, popup failure, CAPTCHA or limitation without bypassing it.

Changing Window Size or user Zoom is not a rebuild test and does not satisfy step 6.

## Status vocabulary

Use only:

- `works`
- `works with limitations`
- `provider blocks embedded login`
- `not offered`
- `not yet tested`

## Matrix

| Site | Authenticated Use | Google SSO | Apple SSO | Popup / Redirect | Restart Restore | Rendering Rebuild Restore | Notes |
|---|---|---|---|---|---|---|---|
| ChatGPT | works | not yet tested | not yet tested | not yet tested | works | works | Real-Mac authenticated use, full app quit/relaunch, and WKWebView rebuild all preserve the login state. |
| Claude | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Gemini | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| X | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Instagram | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| TikTok | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Facebook | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |

## Shared Google-session evidence — Real Mac, 2026-08-09

The accepted Stage 4C baseline was verified against Google-authenticated properties in addition to ChatGPT:

```text
ChatGPT authenticated use                              PASS
Google authenticated state                            PASS
YouTube authenticated state                           PASS
Google login/session visible across FloatTabs Tabs     PASS
Full FloatTabs quit → relaunch preserves login state   PASS
WKWebView rebuild preserves login state                PASS
```

Observed behavior:

- an existing Google authenticated state is visible and reusable across multiple FloatTabs Tabs/Slots without logging in separately;
- after FloatTabs is fully quit and relaunched, the saved login information remains available;
- after a Website Mode or Browser Identity change rebuilds the persistent Slot WKWebView, the authenticated website state remains available.

Together these results are direct Real-Mac evidence that ordinary persistent Slots use the intended shared, persistent `WKWebsiteDataStore.default()` profile rather than isolated per-Tab or in-memory stores.

## Stage 4C acceptance

**PASS.**

The accepted baseline proves:

- normal authenticated use on multiple real sites;
- shared Google session state across persistent Slots;
- full quit/relaunch session persistence;
- session persistence across WKWebView rebuild;
- no observed regression to the already accepted Bilibili Desktop and YouTube behavior.

Fresh Google/Apple OAuth entry flows remain useful compatibility coverage when encountered naturally, but are not required to keep Stage 4C open after the persistent session lifecycle has passed. Provider-specific bypasses, cookie imports, token serialization, or authentication hacks remain prohibited.
