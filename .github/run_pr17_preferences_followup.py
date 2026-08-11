from pathlib import Path

path = Path('.github/pr17_preferences_followup.py')
source = path.read_text()
old = '''def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)
'''
new = '''def replace_once(text, old, new, label):
    count = text.count(old)
    if label == "border appearance functions" and count == 2:
        # PanelRootView has the same generic isOpaque/hitTest skeleton earlier
        # in this file. PanelInteractionBorderView is the later occurrence.
        index = text.rfind(old)
        return text[:index] + new + text[index + len(old):]
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)
'''
if source.count(old) != 1:
    raise SystemExit('replace_once helper shape changed unexpectedly')
source = source.replace(old, new, 1)
exec(compile(source, str(path), 'exec'))
