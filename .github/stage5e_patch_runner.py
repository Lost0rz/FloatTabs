from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: stage5e_patch_runner.py <extracted-apply-script>")

    path = Path(sys.argv[1])
    text = path.read_text()

    old = '''from pathlib import Path

def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"missing replacement anchor in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))
'''

    new = '''from pathlib import Path
import re

def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old in text:
        p.write_text(text.replace(old, new, 1))
        return

    lines = old.splitlines()
    pattern = r"\\n".join(
        r"[ \\t]*" + re.escape(line.lstrip())
        for line in lines
    )
    match = re.search(pattern, text, flags=re.MULTILINE)
    if not match:
        raise SystemExit(f"missing replacement anchor in {path}: {old[:120]!r}")
    p.write_text(text[:match.start()] + new + text[match.end():])
'''

    if old not in text:
        raise SystemExit("could not upgrade extracted replace_once helper")

    path.write_text(text.replace(old, new, 1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
