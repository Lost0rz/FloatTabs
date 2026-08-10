from pathlib import Path

app = Path("FloatTabs/App/AppCoordinator.swift")
text = app.read_text(encoding="utf-8")
old = '''    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        backupService: FloatTabsBackupService = FloatTabsBackupService()
    ) {
        self.preferencesStore = preferencesStore
        self.backupService = backupService

        if let panelController {
'''
new = '''    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        backupService: FloatTabsBackupService = FloatTabsBackupService()
    ) {
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        self.preferencesStore = resolvedPreferencesStore
        self.backupService = backupService

        if let panelController {
'''
if text.count(old) != 1:
    raise RuntimeError("AppCoordinator preferences initializer block not found exactly once")
text = text.replace(old, new, 1)
text = text.replace(
    "                preferencesStore: preferencesStore\n",
    "                preferencesStore: resolvedPreferencesStore\n",
    1,
)
app.write_text(text, encoding="utf-8")

panel = Path("FloatTabs/Panel/PanelController.swift")
text = panel.read_text(encoding="utf-8")
old = '''        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore = AppPreferencesStore()
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.frameStore = frameStore
        self.preferencesStore = preferencesStore
'''
new = '''        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore? = nil
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.frameStore = frameStore
        self.preferencesStore = preferencesStore ?? AppPreferencesStore()
'''
if text.count(old) != 1:
    raise RuntimeError("PanelController preferences initializer block not found exactly once")
panel.write_text(text.replace(old, new, 1), encoding="utf-8")
