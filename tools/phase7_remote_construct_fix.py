#!/usr/bin/env python3
from pathlib import Path

script = Path(__file__).with_name("phase7_remote_construct.py")
text = script.read_text()

# Fix 1: the old residency field occurs in both an inactive plan and a budget
# candidate. Only the inactive-plan construction becomes a retention preference.
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
    raise SystemExit(f"construction fix 1 expected one target, got {text.count(old)}")
text = text.replace(old, new, 1)

# Fix 2: onSetResidency intentionally exists once on ExternalControlZoneView and
# once on ExternalWebAppTabView. Replace both declarations in one asserted step.
old = '''replace_once(
    p,
    "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n",
    ''' + '"""' + '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
''' + '"""' + '''
)
# ExternalWebAppTabView has the same declaration; update the second occurrence.
replace_once(
    p,
    "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n",
    ''' + '"""' + '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
''' + '"""' + '''
)
'''
new = '''replace_all_checked(
    p,
    "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n",
    ''' + '"""' + '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
''' + '"""' + ''',
    minimum=2,
)
'''
if text.count(old) != 1:
    raise SystemExit(f"construction fix 2 expected one target block, got {text.count(old)}")
text = text.replace(old, new, 1)

script.write_text(text)
exec(compile(text, str(script), "exec"), {"__name__": "__main__", "__file__": str(script)})
