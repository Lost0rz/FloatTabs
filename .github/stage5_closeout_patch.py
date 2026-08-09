from pathlib import Path
import re


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


# Lifecycle regression coverage.
p = Path('FloatTabsTests/WebViewPoolTests.swift')
text = p.read_text()
if 'import AppKit\n' not in text:
    text = text.replace('import WebKit\n', 'import AppKit\nimport WebKit\n', 1)
anchor = '    func testWebContentRecoveryPolicyReloadsActiveAndDefersInactiveSlots() {'
tests = '''    func testColdLifecycleReleasesAfterGracePeriod() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Cold")
        profile.residencyPolicy = .cold
        _ = pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
    }

    func testColdLifecycleActivationCancelsPendingRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "ColdCancel")
        profile.residencyPolicy = .cold
        _ = pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)

        lifecycle.activate(profile: profile)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testWarmLifecycleDoesNotScheduleColdRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Warm")
        profile.residencyPolicy = .warm
        _ = pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

'''
if 'testColdLifecycleReleasesAfterGracePeriod' not in text:
    text = replace_once(text, anchor, tests + anchor, 'lifecycle tests anchor')
p.write_text(text)

# Persist non-default policies, not only legacy defaults.
p = Path('FloatTabsTests/ProfileRepositoryTests.swift')
text = p.read_text()
text = replace_once(
    text,
    '''                currentURL: URL(string: "https://example.com/current")!,
                createdAt: Date(timeIntervalSince1970: 100),''',
    '''                currentURL: URL(string: "https://example.com/current")!,
                residencyPolicy: .hot,
                backgroundMediaPolicy: .allowBackgroundAudio,
                createdAt: Date(timeIntervalSince1970: 100),''',
    'policy round-trip fixture'
)
text = replace_once(
    text,
    '''            XCTAssertEqual(restored.profiles.first?.currentURL, profile.currentURL)
            XCTAssertEqual(restored.lastActiveTabID, id)''',
    '''            XCTAssertEqual(restored.profiles.first?.currentURL, profile.currentURL)
            XCTAssertEqual(restored.profiles.first?.residencyPolicy, .hot)
            XCTAssertEqual(restored.profiles.first?.backgroundMediaPolicy, .allowBackgroundAudio)
            XCTAssertEqual(restored.lastActiveTabID, id)''',
    'policy round-trip assertions'
)
p.write_text(text)

# Architecture source of truth.
p = Path('docs/architecture/FloatTabs_Technical_Architecture_v1.2.md')
text = p.read_text()
new_section = '''# 5. WKWebView Ownership & Lifecycle

`Active` is a presentation state, not a residency tier. Each `WebAppProfile` persists a user-selected residency policy that controls what FloatTabs does after the Slot becomes inactive:

```swift
enum SlotResidencyPolicy: String, Codable {
    case hot
    case warm
    case cold
}
```

`WebViewPool` still owns one live `WKWebView` per resident Slot. FloatTabs never cycles every Slot through one shared WKWebView.

## 5.1 Hot

Hot is for state-heavy Web Apps where return-to-interaction latency matters more than memory.

- once the Slot has been activated in the current app process, keep its live WKWebView attached;
- each Hot Slot owns an independent `WebSlotHostView`;
- when inactive, freeze that host's viewport before another Slot changes panel size;
- only the active Hot host follows live panel resizing;
- FloatTabs does not proactively detach or evict a Hot WebView;
- Hot does not eagerly preload every configured Hot Slot at app launch;
- macOS/WebKit may still terminate a content process under system pressure, in which case normal Stage 4 recovery applies.

The independent host is mandatory. Do not reintroduce the rejected shared-variable-host experiment that resized multiple resident WebViews through one changing viewport; that polluted `frame → pageZoom → CSS viewport` state across Slots.

## 5.2 Warm

Warm is the default.

- keep the WKWebView object in `WebViewPool`;
- detach it from visible presentation while inactive;
- re-selection reuses the same WKWebView;
- DOM / SPA / scroll / unsent text preservation remains best-effort because WebKit may throttle or suspend detached content;
- do not proactively evict Warm WebViews merely because they are inactive.

## 5.3 Cold

Cold trades state fidelity for memory.

```text
inactive Cold Slot
→ 30-second grace period
→ release live WKWebView/runtime if still inactive
```

Cold release removes transient WebView/navigation/popup runtime only. It must retain:

- `WebAppProfile`;
- `homeURL`;
- `currentURL`;
- rendering profile;
- residency/media settings;
- persistent `WKWebsiteDataStore.default()` data.

Cold restore therefore guarantees only persistent login data where the site permits it plus the persisted current URL. It does not guarantee unsent text, exact scroll position, or SPA transient memory.

Reactivating a Cold Slot during the grace period cancels the pending release.

## 5.4 Background Media

Background-media policy is persisted separately from residency:

```swift
enum BackgroundMediaPolicy: String, Codable {
    case pauseWhenInactive
    case allowBackgroundAudio
}
```

`Pause When Inactive` uses `WKWebView.pauseAllMediaPlayback()` when the Slot becomes inactive. Do not use `setAllMediaPlaybackSuspended(true/false)` for routine Slot switching; Real-Mac testing showed the stronger suspension API can leave normal user Play interactions blocked after fast switching.

`Allow Background Audio` means FloatTabs does not explicitly pause or suspend that resident WebView. It is a permission from FloatTabs, not a guarantee that the website will continue playback. Site implementation and Website Mode may still pause when the view is inactive/detached. Observed Real-Mac behavior includes:

- Bilibili can continue in Warm/Cold-pending while resident;
- YouTube Desktop can continue in Warm while resident;
- YouTube Mobile pauses when Warm/detached;
- YouTube Hot can continue because its WebView remains attached.

Do not add site-specific JavaScript autoplay bypasses or broaden autoplay permissions merely to force parity.

## 5.5 Resource Measurement

The residency model is user-controlled; FloatTabs must not silently demote Hot → Warm/Cold.

After functional acceptance, benchmark 1 / 3 / 6 Slot combinations with Instruments for:

- host + WebContent memory;
- CPU;
- Energy Impact;
- network activity;
- switch latency.

Use those measurements for future warnings/default tuning, not for hidden policy overrides.

No `Keep Active in Memory` field belongs in the Add/Edit Web App form; residency is configured from the Slot context menu.

Memory pressure handling remains separate from authentication persistence. Destroying a WKWebView must never clear the persistent website data store.

---

# 6. Browser Profile & Login Session Architecture'''
text, count = re.subn(
    r'# 5\. WKWebView Ownership & Lifecycle\n.*?\n---\n\n# 6\. Browser Profile & Login Session Architecture',
    new_section,
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit(f'architecture lifecycle section: expected 1 match, found {count}')
text = replace_once(
    text,
    '''- rendering profile;
- creation/last-used metadata.''',
    '''- rendering profile;
- residency policy;
- background-media policy;
- creation/last-used metadata.''',
    'architecture profile metadata'
)
p.write_text(text)

# Product source of truth.
p = Path('docs/product/FloatTabs_Product_Development_Spec_v0.5.md')
text = p.read_text()
menu_section = '''## 6.1 Slot Context Menu

Slot 右键菜单管理 Slot 身份与资源策略，不模拟完整浏览器：

```text
Return to Home
────────────
Residency
  Hot
  Warm
  Cold
Background Media
  Pause When Inactive
  Allow Background Audio
────────────
Edit Web App…
────────────
Remove Web App…
```

`Edit Web App…` 已包含 Name，因此不再提供独立 `Rename` 动作。排序继续使用拖拽；`⌘1…⌘9` 始终跟随当前排序。

`Residency` 不参与排序：拖拽只改变 Slot 顺序，右键设置只改变资源生命周期。

`Return to Home` 导航到稳定的 `homeURL`，不主动清空 WebKit back/forward history。熟练用户也可使用 `⌘⇧H`。

---

# 7. Rendering Profile — 四层独立'''
text, count = re.subn(
    r'## 6\.1 Slot Context Menu\n.*?\n---\n\n# 7\. Rendering Profile — 四层独立',
    menu_section,
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit(f'product context menu: expected 1 match, found {count}')

residency_section = '''## 13.1 Slot Residency Policy

`Active` 不是资源等级；当前选中的 Slot 永远是 Active / 可交互状态。每个 Slot 另外持久化：

```text
Residency: Hot / Warm / Cold
Background Media: Pause When Inactive / Allow Background Audio
```

### Hot

- 第一次在当前 app process 中激活后，live WKWebView 保持 attached；
- 每个 Hot Slot 使用独立 presentation host；
- inactive 时冻结自己的 viewport，不跟随其他 Slot 的 Window Size 改变；
- FloatTabs 不主动 detach / evict；
- 不要求 app launch 时预加载所有 Hot Slot；
- 适合长 ChatGPT conversation 等重型 SPA。

### Warm

- 默认值；
- WKWebView 保留在 pool；
- inactive 时从 visible presentation detach；
- 再次选择时复用同一个 WKWebView；
- 页面内存状态由 WebKit best-effort 保留，不做强保证。

### Cold

```text
inactive
→ 30 秒 grace period
→ 仍未激活则 release live WKWebView
```

Cold release 保留：

- WebAppProfile；
- Home URL；
- Current URL；
- Rendering Profile；
- Residency / Background Media；
- persistent WebKit website data。

30 秒内重新激活必须取消 pending release。

## 13.2 Persistent Website Data

所有普通 Slots 默认：

```swift
WKWebsiteDataStore.default()
```

用于保存：

- cookies；
- login/session；
- localStorage；
- IndexedDB / website storage；
- cache。

V1 = 一个 FloatTabs browser profile。

同域名多个 Slot 默认共享同一登录状态。

多账号隔离 / 多 profile 放到 V2。

FloatTabs 不保存密码，不手工 serialize auth Cookie/token。

## 13.3 Background Media

`Pause When Inactive`：

```text
inactive
→ WKWebView.pauseAllMediaPlayback()
```

只执行可由用户重新 Play 的普通暂停。不要在常规 Slot switching 使用 `setAllMediaPlaybackSuspended(true/false)`；Real-Mac 已验证强 suspension 会造成 YouTube/B站播放按钮恢复异常。

`Allow Background Audio`：

> FloatTabs 不主动 pause / suspend；**不等于网站一定会继续后台播放。**

是否继续由站点 + Website Mode 决定。当前 Real-Mac 观察：

- B站 Warm / Cold-pending 可继续；Cold eviction 后停止；
- YouTube Desktop + Warm 可继续；
- YouTube Mobile + Warm 会自行暂停；
- YouTube Hot 因 WebView 保持 attached 可继续。

不为此增加 YouTube/B站域名特判、JS 强制 `play()` 或 autoplay bypass。

## 13.4 Resource Measurement

Hot/Warm/Cold 是用户显式策略，FloatTabs 不静默自动降级 Hot。

功能验收后再用 Instruments 测量：

```text
1 Slot
3 Slots
6 Slots
```

记录：

- Memory；
- CPU；
- Energy；
- Network；
- switch latency。

测量结果用于默认值、提示和后续优化，不用于破坏用户显式 Residency 选择。

V1 Add/Edit form 仍不放 `Keep Active in Memory`；Residency 由 Slot context menu 管理。

---

# 14. Login / OAuth'''
text, count = re.subn(
    r'## 13\.1 One Warm WebView per Slot\n.*?\n---\n\n# 14\. Login / OAuth',
    residency_section,
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit(f'product residency section: expected 1 match, found {count}')

stage5 = '''## Stage 5 — Slot Residency & Resource Optimization

- per-Slot `Hot / Warm / Cold` Residency Policy；
- Hot independent presentation host，禁止 shared variable viewport；
- Warm pooled/detached reuse；
- Cold 30 秒 grace + live WebView eviction；
- `Pause When Inactive` 使用 user-resumable media pause；
- `Allow Background Audio` 作为 FloatTabs permission，实际能力由站点 / Website Mode 决定；
- Real-Mac compatibility acceptance；
- Instruments 1/3/6 Slot Memory / CPU / Energy / Network / switch-latency benchmark；
- 根据测量决定是否需要 Hot-count warning / Cold timing tuning，不静默覆盖用户策略。
'''
text, count = re.subn(
    r'## Stage 5 — Resource Optimization\n.*?\n(?=## Stage 6 — Polish / Release)',
    stage5 + '\n',
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit(f'product stage5 section: expected 1 match, found {count}')
text = replace_once(
    text,
    '#20 Suspend background WebViews/media + benchmark',
    '#20 Add Hot/Warm/Cold residency + background-media policy + benchmark',
    'development issue #20'
)
p.write_text(text)

# Dedicated Stage 5 note.
p = Path('docs/product/FloatTabs_Stage_5_Residency_Policy.md')
text = p.read_text()
text = replace_once(
    text,
    '''- FloatTabs does not proactively detach or evict the live `WKWebView`.
- Each Hot Slot owns an independent AppKit presentation host.''',
    '''- FloatTabs does not proactively detach or evict the live `WKWebView` after that Slot has been activated in the current app process.
- Hot does not eagerly preload every configured Hot Slot at app launch.
- Each Hot Slot owns an independent AppKit presentation host.''',
    'stage5 hot launch semantics'
)
text = replace_once(
    text,
    '''- `Allow Background Audio` leaves media untouched while the WebView remains resident; FloatTabs does not force playback.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.''',
    '''- `Allow Background Audio` leaves media untouched while the WebView remains resident; FloatTabs does not force playback.
- Background continuation is website/Website-Mode dependent. Real-Mac observations: Bilibili Warm/Cold-pending can continue; YouTube Desktop Warm can continue; YouTube Mobile Warm pauses itself; YouTube Hot can continue while attached.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.''',
    'stage5 media compatibility note'
)
p.write_text(text)

print('Stage 5 closeout patch applied')
