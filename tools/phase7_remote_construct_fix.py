#!/usr/bin/env python3
from pathlib import Path

script = Path(__file__).with_name("phase7_remote_construct.py")
text = script.read_text()

# 1. Scope the duplicate residency literal to the InactivePlan initializer.
old1 = """replace_once(
    p,
    \"            residencyPolicy: profile.residencyPolicy,\\n\",
    \"            retentionPreference: profile.runtimeRetentionPreference,\\n\"
)
"""
new1 = """replace_once(
    p,
    '''        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            residencyPolicy: profile.residencyPolicy,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )''',
    '''        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            retentionPreference: profile.runtimeRetentionPreference,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )'''
)
"""
if text.count(old1) != 1:
    raise SystemExit(f"fix1 expected one transform block, got {text.count(old1)}")
text = text.replace(old1, new1, 1)

# 2. The rail and tab view intentionally have the same callback declaration.
old2 = """replace_once(
    p,
    \"    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n\",
    '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
'''
)
# ExternalWebAppTabView has the same declaration; update the second occurrence.
replace_once(
    p,
    \"    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n\",
    '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
'''
)
"""
new2 = """replace_all_checked(
    p,
    \"    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\\n\",
    '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
''',
    minimum=2,
)
"""
if text.count(old2) != 1:
    raise SystemExit(f"fix2 expected one transform block, got {text.count(old2)}")
text = text.replace(old2, new2, 1)

# 3. WebViewPool performs recovery disposition inline in a switch.
old3 = """replace_once(
    p,
    '''        let recoveryDisposition = Self.recoveryDisposition(
            isActive: isActive,
            residencyPolicy: residencyPolicy
        )
''',
    '''        let recoveryDisposition = Self.recoveryDisposition(
            isActive: isActive,
            runtimeRetentionPreference: runtimeRetentionPreference
        )
'''
)
"""
new3 = """replace_once(
    p,
    '''        switch Self.recoveryDisposition(
            isActive: isActive,
            residencyPolicy: residencyPolicy
        ) {
''',
    '''        switch Self.recoveryDisposition(
            isActive: isActive,
            runtimeRetentionPreference: runtimeRetentionPreference
        ) {
'''
)
"""
if text.count(old3) != 1:
    raise SystemExit(f"fix3 expected one transform block, got {text.count(old3)}")
text = text.replace(old3, new3, 1)

script.write_text(text)
exec(compile(text, str(script), "exec"), {"__name__": "__main__", "__file__": str(script)})
