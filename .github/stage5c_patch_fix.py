from pathlib import Path

path = Path('.github/stage5c_patch.py')
text = path.read_text(encoding='utf-8')
old = '        pinControl.isPinned = isPinned\n'
new = '        pinControl.setPinned(isPinned)\n'
if old not in text:
    raise SystemExit('expected pin assignment not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
