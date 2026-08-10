from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "FloatTabs/Web/SlotLifecycleCoordinator.swift",
    "    static let defaultWarmReleaseDelay: TimeInterval = 180\n",
    "    static let defaultWarmReleaseDelay: TimeInterval = 120\n",
)

replace_once(
    "FloatTabsTests/WebViewPoolTests.swift",
    "    func testWarmLifecycleDoesNotScheduleColdRelease() async throws {\n",
    "    func testResourceLifecycleDefaultTimingsMatchAcceptedContract() {\n"
    "        XCTAssertEqual(SlotLifecycleCoordinator.defaultColdReleaseDelay, 30)\n"
    "        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmReleaseDelay, 120)\n"
    "        XCTAssertEqual(SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay, 120)\n"
    "        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmResidentLimit, 2)\n"
    "    }\n\n"
    "    func testWarmLifecycleDoesNotScheduleColdRelease() async throws {\n",
)

replace_once(
    "docs/product/FloatTabs_Stage_5E_Resource_Lifecycle.md",
    "Status: implementation + automated validation in progress on Draft PR #10.\n",
    "Status: accepted Stage 5 resource-lifecycle contract; final closeout validated on PR #10.\n",
)
replace_once(
    "docs/product/FloatTabs_Stage_5E_Resource_Lifecycle.md",
    "- Default inactive TTL: **180 seconds**.\n",
    "- Default inactive TTL: **120 seconds**.\n",
)
replace_once(
    "docs/product/FloatTabs_Stage_5E_Resource_Lifecycle.md",
    "The menu-bar status item displays the current selected Web App name. This remains visible when the panel is hidden, so the user can see which Slot will be presented on the next summon.\n",
    "The menu-bar status item displays the current selected Web App favicon plus name. This remains visible when the panel is hidden, so the user can see which Slot will be presented on the next summon.\n",
)
replace_once(
    "docs/product/FloatTabs_Stage_5E_Resource_Lifecycle.md",
    "These fields are the basis for the following long-duration resource benchmark phase.\n",
    "These fields are the basis for long-duration resource measurement. Real-Mac acceptance on 2026-08-10 confirmed Cold 30-second eviction, Warm timed eviction, hidden recent-active grace, zero-resident recovery, and low post-release idle CPU. The final Warm TTL is intentionally compressed from 180 seconds to 120 seconds to favor memory efficiency while retaining a two-minute quick-return cache window.\n",
)

replace_once(
    "tools/benchmark/floattabs_lifecycle_benchmark.py",
    "PRODUCT_WARM_TTL_SECONDS = 180\n",
    "PRODUCT_WARM_TTL_SECONDS = 120\n",
)
replace_once(
    "tools/benchmark/floattabs_lifecycle_benchmark.py",
    "        warm_inactive=210,\n",
    "        warm_inactive=150,\n",
)
replace_once(
    "tools/benchmark/floattabs_lifecycle_benchmark.py",
    "    # and 180s Warm TTL (120 + 180 for the hidden-selected Warm release).\n",
    "    # and 120s Warm TTL (120 + 120 for the hidden-selected Warm release).\n",
)
replace_once(
    "tools/benchmark/floattabs_lifecycle_benchmark.py",
    "        warm_inactive=230,\n",
    "        warm_inactive=170,\n",
)
replace_once(
    "tools/benchmark/floattabs_lifecycle_benchmark.py",
    "        hidden_warm=340,\n",
    "        hidden_warm=280,\n",
)

replace_once(
    "tools/benchmark/README.md",
    "5. Warm inactive past the 180s Warm TTL;\n",
    "5. Warm inactive past the 120s Warm TTL;\n",
)
replace_once(
    "tools/benchmark/README.md",
    "9. Warm selected + panel hidden past 120s hidden grace + 180s Warm TTL;\n",
    "9. Warm selected + panel hidden past 120s hidden grace + 120s Warm TTL;\n",
)

replace_once(
    "docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md",
    "> Status: measurement plan / Draft PR baseline\n",
    "> Status: Stage 5 benchmark closeout baseline; final resource-lifecycle tuning validated on PR #10\n",
)
replace_once(
    "docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md",
    "6. Is any tuning justified for Hot-count warnings or the Cold grace period?\n",
    "6. Is any tuning justified for Hot-count warnings, Warm cache timing, or the Cold grace period?\n",
)
replace_once(
    "docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md",
    "- keep current defaults unchanged;\n",
    "- keep or tune current defaults based on repeatable Real-Mac evidence;\n",
)

print("Stage 5 closeout patch applied")
