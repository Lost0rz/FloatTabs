from pathlib import Path

path = Path('.github/stage5_closeout_patch.py')
text = path.read_text()
old = '''- `Allow Background Audio` leaves media untouched while the WebView remains resident; FloatTabs does not force playback.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.'''
new = '''- `Allow Background Audio` does not issue any FloatTabs media pause/suspend command while the WebView remains resident.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.'''
if text.count(old) != 1:
    raise SystemExit(f'expected one matcher to repair, found {text.count(old)}')
path.write_text(text.replace(old, new, 1))
