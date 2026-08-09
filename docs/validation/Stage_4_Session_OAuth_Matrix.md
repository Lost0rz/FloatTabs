# Stage 4 Session / OAuth Compatibility Matrix

> Status: IN PROGRESS
> Baseline commit: `8758cc587f9e74665126f3ebdcbf78c8e130bce5`
> Frozen app Bundle Identifier: `com.lost0rz.FloatTabs`

## Purpose

This matrix records real website authentication and session behavior after the Stage 4 navigation/popup layer has passed automated and Real-Mac acceptance.

Do not infer support from the existence of a popup alone. Record the actual flow each provider exposes.

## Required sequence per site

For each site that you can reasonably log into:

1. launch the current Stage 4 build;
2. open or create the site's persistent FloatTabs Slot;
3. start the site's normal login flow;
4. if the site offers Google/Apple SSO, test the offered method separately when practical;
5. confirm the parent Slot becomes authenticated;
6. quit FloatTabs completely with `Cmd+Q` or the menu-bar Quit action;
7. relaunch FloatTabs and confirm the site is still authenticated;
8. change **Browser Identity** or **Website Mode** once so that the Slot's WKWebView is rebuilt;
9. confirm the same authenticated website session is still available after the rebuild;
10. record any provider warning, blocked embedded login, popup failure, CAPTCHA or limitation without bypassing it.

Changing Window Size or user Zoom is not a rebuild test and does not satisfy step 8.

## Status vocabulary

Use only:

- `works`
- `works with limitations`
- `provider blocks embedded login`
- `not offered`
- `not yet tested`

## Matrix

| Site | Direct Login | Google SSO | Apple SSO | Popup / Redirect | Restart Restore | Rendering Rebuild Restore | Notes |
|---|---|---|---|---|---|---|---|
| ChatGPT | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Claude | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Gemini | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| X | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Instagram | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| TikTok | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |
| Facebook | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | not yet tested | |

## Minimum 4C acceptance set

Stage 4 does not require every provider above to work. Providers are allowed to block embedded browsers.

Before 4C can be accepted, record at least:

- two real sites whose normal login/session works end-to-end;
- one complete quit/relaunch session-restore result;
- one complete Browser Identity or Website Mode rebuild-restore result;
- one OAuth/SSO flow when a tested site offers it, or an explicit provider-blocked result;
- no regression to the accepted Bilibili Desktop / YouTube fullscreen behavior.

If a provider blocks embedded authentication, record it as `provider blocks embedded login`; do not add cookie import, auth bypass, user-agent spoofing beyond the existing user-selected Browser Identity, or provider-specific JavaScript hacks.
