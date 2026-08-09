from pathlib import Path

path = Path('.github/stage5d-core-refinement.py')
text = path.read_text()
needle = '        webView.customUserAgent = UserAgentProvider.customUserAgent('
replacement = '        if let customUserAgent = UserAgentProvider.customUserAgent('
count = text.count(needle)
if count != 2:
    raise SystemExit(f'expected 2 helper anchor occurrences, got {count}')
path.write_text(text.replace(needle, replacement))
print('fixed WebViewFactory runtime-rendering anchor')
