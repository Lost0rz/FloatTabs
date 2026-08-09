from pathlib import Path

path = Path('.github/benchmark_auto_control_patch.py')
text = path.read_text()
replacements = {
    'print(f"\\nDebug benchmark control: CONNECTED': 'print(f"\\\\nDebug benchmark control: CONNECTED',
    'print(f"\\nDebug benchmark control: unavailable': 'print(f"\\\\nDebug benchmark control: unavailable',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f'expected one match for {old!r}, found {text.count(old)}')
    text = text.replace(old, new, 1)
path.write_text(text)
