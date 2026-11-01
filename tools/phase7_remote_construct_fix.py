#!/usr/bin/env python3
from pathlib import Path

script = Path(__file__).with_name("phase7_remote_construct.py")
text = script.read_text()
old = '''replace_once(
    p,
    "            residencyPolicy: profile.residencyPolicy,\\n",
    "            retentionPreference: profile.runtimeRetentionPreference,\\n"
)
'''
new = '''replace_once(
    p,
    ''' + '"""' + '''        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            residencyPolicy: profile.residencyPolicy,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )''' + '"""' + ''',
    ''' + '"""' + '''        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            retentionPreference: profile.runtimeRetentionPreference,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )''' + '"""' + '''
)
'''
if text.count(old) != 1:
    raise SystemExit(f"construction fix expected one target, got {text.count(old)}")
text = text.replace(old, new, 1)
script.write_text(text)
exec(compile(text, str(script), "exec"), {"__name__": "__main__", "__file__": str(script)})
