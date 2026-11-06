# FloatTabs Automatic Recent 120s Policy Delta V1

**Authority:** Approved Issue [#203, revision 3](https://github.com/Lost0rz/FloatTabs/issues/203), SHA256 `ddaf0d9e4b98bbc1cbf4c21aed9c7bc383daaabc673d9b2f8d5132685120246d`.
**State:** Prospective amendment; effective in the product only after this change is merged to `main`.

## Bounded policy change

This amendment supersedes only Runtime Lifecycle Policy V7's initial 30-second Automatic Recent boundary. Automatic inactive Runtime stages are:

| Stage | Inactive age | Normal-pressure behavior |
| --- | --- | --- |
| `RECENT` | `[0, 120)` seconds | Remains resident |
| `IDLE` | `[120, 600)` seconds | Remains resident |
| `LONG_IDLE` | `600` seconds or more | Eligible for normal reclaim if still inactive and unprotected |

The existing 600-second Long Idle threshold remains unchanged. Reactivation still invalidates the prior inactivity plan; current Runtime identity, generation, media, visibility, fullscreen, restoration, and other existing protection checks still govern reclaim eligibility. Warning pressure still waits until `IDLE`; critical pressure may bypass `RECENT` for an eligible unprotected Automatic Runtime.

`Keep Loaded` remains protected from automatic reclaim. Browser Profile, cookies, login/session state, and website data remain independent from disposable WebView Runtime lifetime. This timing adjustment does not add a resident-count or RAM budget, change pressure policy, or change recovery behavior.

## Verification boundary

Use a controlled monotonic clock and scheduler to verify `119s → RECENT`, `120s → IDLE`, `599s → IDLE`, and `600s → LONG_IDLE` with one eligible normal reclaim. Re-activation, Keep Loaded, generation/media/visibility protection, and warning/critical pressure behavior remain regression boundaries. Historical Policy V7 text is retained as the original WP2 record; this prospective delta is its bounded timing amendment.
