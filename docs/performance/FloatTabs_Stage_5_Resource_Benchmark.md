# FloatTabs — Stage 5 Resource Benchmark Protocol

> Status: measurement plan / Draft PR baseline
> Base: `main` after Stage 5 Residency Policy merge (`f74500246e30514a3fd1ddb89ed5c64a903da575`)
> Scope: measurement and tuning only; no change to accepted Hot / Warm / Cold semantics without separate evidence and review.

## 1. Goal

Stage 5 functional Residency behavior is already accepted. This follow-up measures the real resource cost of the accepted policies on a Real Mac so future defaults, warnings, or timing changes are data-driven.

This PR must answer:

1. What is the incremental resource cost of 1 / 3 / 6 resident Slots?
2. How much does Hot cost relative to Warm when inactive?
3. How much memory is actually recovered by Cold after its 30-second grace period?
4. Does inactive media or site polling create sustained CPU / Energy / Network activity?
5. What switch-latency benefit does Hot provide for state-heavy pages such as a long ChatGPT conversation?
6. Is any tuning justified for Hot-count warnings or the Cold grace period?

## 2. Non-goals

This benchmark PR does not:

- redesign Hot / Warm / Cold;
- silently demote a user-selected Residency policy;
- add site-specific autoplay hacks;
- change Website Mode / Window Size / Zoom semantics;
- change navigation, login, session, upload, download, or WebContent recovery behavior;
- optimize based on CI-host measurements alone.

## 3. Measurement environment

Record before every benchmark pass:

- Mac model / SoC;
- RAM;
- macOS version;
- FloatTabs commit SHA;
- power source: AC or battery;
- display count and resolution;
- active VPN / proxy if relevant;
- whether Developer Tools / Instruments are attached;
- browser/site login state;
- Website Mode and Window Size for every test Slot.

Use one fixed Real-Mac environment for comparisons within a benchmark series.

## 4. Metrics

Capture both FloatTabs host and WebKit child-process behavior.

### Memory

- FloatTabs host RSS;
- total FloatTabs-responsible WebContent RSS;
- Networking / GPU helper RSS when attributable;
- total FloatTabs process-tree RSS;
- memory delta from baseline.

### CPU

- FloatTabs host CPU%;
- aggregate FloatTabs-responsible WebContent CPU%;
- 60-second idle average;
- peak during Slot switch.

### Energy

Use Instruments Energy Log / Activity Monitor Energy Impact where available.

Record:

- active interaction;
- inactive resident state;
- app hidden state.

### Network

Record sustained network activity after pages have reached steady state. Distinguish site-owned polling/streaming from FloatTabs-triggered reloads.

### Switch latency

Measure from Slot-selection input to the destination Slot being visually present and usable.

Record separately:

- simple page;
- long ChatGPT conversation;
- video page;
- Cold recreation.

Do not mix network-cold-load time with Hot/Warm presentation latency.

## 5. Test matrix

Every core comparison uses the same Slot content and order.

### A. One Slot baseline

Run each policy independently:

- 1 Hot;
- 1 Warm;
- 1 Cold active;
- 1 Cold after >30 seconds inactive and eviction.

Purpose: establish host/runtime fixed cost and single-WebView cost.

### B. Three Slots

Run:

- 3 Hot;
- 3 Warm;
- 3 Cold after eviction;
- mixed: 1 Hot + 1 Warm + 1 Cold.

Purpose: estimate incremental resident-WebView cost and validate mixed-policy behavior.

### C. Six Slots

Run:

- 6 Hot;
- 6 Warm;
- 6 Cold after eviction;
- mixed representative set: 2 Hot + 2 Warm + 2 Cold.

Purpose: identify whether scaling remains acceptable for the intended small, high-frequency Web App set.

## 6. Workloads

Use two workload classes.

### Controlled workload

Use stable pages with no intentional media playback to measure FloatTabs/WebKit residency overhead with minimal site noise.

### Representative real-site workload

Use the current priority compatibility set, with at least:

- ChatGPT: long conversation / state-heavy SPA;
- YouTube Desktop: video page;
- YouTube Mobile: same account/content class where possible;
- Bilibili Desktop: video page.

Real-site numbers must be labelled as observational because site scripts, ads, recommendations, polling, login state and CDN behavior vary over time.

## 7. State checkpoints

For every configuration capture these checkpoints after the system reaches steady state:

```text
S0  App launched, before test Slots are activated
S1  All required Slots activated once
S2  Active Slot idle for 60 s
S3  Non-active resident Slots idle for 60 s
S4  FloatTabs panel hidden for 60 s
S5  Cold Slots inactive >30 s and evicted
S6  First return to each policy
S7  Repeated switch loop
```

The benchmark must not assume a configured Hot Slot has a live WebView before it has been activated in the current app process.

## 8. Repetition

For latency and CPU comparisons:

- discard the first warm-up switch where appropriate;
- run at least 10 repeated switches;
- report median;
- report p95 when sample count is sufficient;
- record obvious outliers separately rather than silently deleting them.

For memory / idle CPU / Energy:

- use at least three repeated steady-state samples per configuration;
- keep the same observation window.

## 9. Required result tables

### Residency scaling

| Slots | Policy | Host RSS | WebContent RSS | Total RSS | Idle CPU | Energy | Network idle |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Hot | | | | | | |
| 1 | Warm | | | | | | |
| 1 | Cold evicted | | | | | | |
| 3 | Hot | | | | | | |
| 3 | Warm | | | | | | |
| 3 | Cold evicted | | | | | | |
| 6 | Hot | | | | | | |
| 6 | Warm | | | | | | |
| 6 | Cold evicted | | | | | | |

### Switch latency

| Workload | From | To | Median | p95 | Notes |
|---|---|---|---:|---:|---|
| ChatGPT long conversation | Warm/other | Hot ChatGPT | | | |
| ChatGPT long conversation | other | Warm ChatGPT | | | |
| Controlled page | other | Hot | | | |
| Controlled page | other | Warm | | | |
| Controlled page | other | Cold evicted | | | |

## 10. Decision rules

Measurements may justify a follow-up change only if the evidence is repeatable and the product trade-off is explicit.

Potential outcomes:

- keep current defaults unchanged;
- add a non-blocking warning when many Hot Slots are selected;
- tune the Cold grace period;
- improve inactive scheduling without changing user-visible Residency semantics;
- identify a FloatTabs-owned sustained CPU/network defect and fix it in a separate focused commit/PR section.

Do not infer a FloatTabs defect solely from a real site's own background polling or media policy.

## 11. Closeout criteria

This benchmark PR is complete when:

- 1 / 3 / 6 Slot matrices are recorded on a Real Mac;
- Hot / Warm / Cold memory deltas are quantified;
- hidden-app idle CPU / Energy behavior is measured;
- representative network-idle behavior is recorded;
- Hot vs Warm switch latency is measured for a long ChatGPT conversation;
- Cold recreation latency and recovered memory are measured;
- any recommended tuning is separated into evidence-backed changes;
- Stage 5 product semantics remain unchanged unless a specific measured problem warrants a separately reviewed adjustment.
