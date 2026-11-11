# FloatTabs — Project Context and Technical Boundaries

FloatTabs is a native macOS floating Web App container, not a general-purpose browser. Product priorities are user experience, stability, runtime correctness, and diagnosability. Do not expand instrumentation or abstraction at the expense of those product goals.

This file describes **FloatTabs-specific** source boundaries and safety constraints. The installed Engineering Governance plugin owns generic task/workflow authorization, Skill routing, verification policy, reviews, delivery, and lifecycle. This file defines no governance control mode, approver, delegation permission, or CI test-selection procedure.

## Documentation and source navigation

- `docs/README.md` indexes currently applicable product/architecture contracts, historical plans, design evidence, and supersession.
- `docs/architecture/DOMAIN_MAP.md` maps Domains, canonical writers, implementation entry points, and related tests.
- Historical Stage/WP plans, dated audits, acceptance reports, and archived files are evidence from their original scope, not current implementation facts. Verify current behavior against applicable bounded contracts and source/tests.

## Canonical product ownership

- **Tabs / Profiles:** own persistent Tab/Profile identity, selection, order, and configuration projection, independent of live Runtime residency.
- **Web:** owns `WKWebView` creation, navigation, observer lifetime, health, and recovery. `SlotLifecycleCoordinator` alone decides lifecycle/reclaim policy. `WebViewPool` implements Runtime creation, retention, release, and restore; it must not introduce an independent reclaim policy.
- **Panel / Window / Fullscreen:** own presentation and exact selected-Slot/window synchronization.
- **Focus / Input:** own native/DOM focus and command/event routing; stale Runtime callbacks must not focus or present a different Slot.
- **Persistence:** owns configuration, Browser Profile/Session state, and recovery material independently of WebView lifetime.
- **Attention:** consumes bounded Web/Slot generation facts without becoming a Runtime or persistence writer.
- **Diagnostics:** records bounded observations and privacy-safe evidence; it is not a second source of product truth.

Preserve single-writer state ownership. Do not conceal Runtime defects by resetting persistence, forcing unrelated reloads, or silently replacing user configuration.

## FloatTabs Runtime and platform constraints

- Bind incident evidence, when available, to build/source identity, Slot and Session, WebView/Runtime generation, navigation generation, timestamps, and recovery request/outcome. Do not combine stale generations into one incident.
- A successful reload, reset, or restart proves a recovery boundary, not a WebKit root cause. Unsupported causal claims remain `ROOT CAUSE UNKNOWN`.
- Real macOS/WebKit behavior, TCC, multi-display focus, installed app provenance, and user interaction need evidence from an actual Mac; repository or simulated browser observations cannot establish those runtime facts.
- Public WebKit APIs cannot reliably attribute all WebContent/GPU process memory to FloatTabs. Runtime count must not be represented as a measured aggregate GiB footprint.

## Project CI environment and data safety

- Product macOS builds run on Apple Silicon. The established self-hosted runner labels are `[self-hosted, macOS, ARM64, mac-mini-ci]`. Runner definitions and test commands live in `.github/workflows/` and `tools/ci/`, not in this file.
- The repository is public: untrusted fork PR code must not run on the private self-hosted Mac runner.
- Browser Profiles, Slot configuration, website/session data, preferences, backups, and recovery material are user data. Runtime recovery or diagnostics must not delete them, or turn unreadable persistent configuration into an empty fallback, without an explicit product/data-loss decision.
