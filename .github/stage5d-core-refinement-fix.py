from pathlib import Path

path = Path('.github/stage5d-core-refinement.py')
text = path.read_text()

runtime_needle = '        webView.customUserAgent = UserAgentProvider.customUserAgent('
runtime_replacement = '        if let customUserAgent = UserAgentProvider.customUserAgent('
count = text.count(runtime_needle)
if count != 2:
    raise SystemExit(f'expected 2 runtime helper anchor occurrences, got {count}')
text = text.replace(runtime_needle, runtime_replacement)

old_test_name = '    func testWebsiteLayoutScaleKeepsDesktopAndMobileIndependentFromWindowSize() {\\n'
new_test_name = '    func testWebsiteLayoutViewportSeparatesTargetCSSWidthFromVisibleWindowSize() {\\n'
if old_test_name not in text:
    raise SystemExit('helper test insertion anchor not found')
text = text.replace(old_test_name, new_test_name, 1)

path.write_text(text)
print('fixed WebViewFactory runtime-rendering and test anchors')
