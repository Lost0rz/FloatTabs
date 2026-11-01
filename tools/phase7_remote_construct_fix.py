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

# The original transformer contains two intentionally broader assumptions:
# 1) the rail callback declaration appears twice;
# 2) WebViewPool's recovery disposition is actually an inline switch, not a
#    temporary local variable. Override only those exact replace_once requests.
marker = "# -----------------------------------------------------------------------------\n# WP1 — canonical retention model with additive legacy compatibility."
if text.count(marker) != 1:
    raise SystemExit("construction wrapper could not locate WP1 marker")
wrapper = r'''
_original_replace_once = replace_once
_rail_retention_callback_replaced = False
_recovery_switch_replaced = False

def replace_once(path, old, new):
    global _rail_retention_callback_replaced, _recovery_switch_replaced

    rail_old = "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n"
    if old == rail_old:
        if _rail_retention_callback_replaced:
            return
        source = read(path)
        count = source.count(old)
        if count != 2:
            raise SystemExit(
                f"{path}: expected exactly two rail residency callback declarations, got {count}"
            )
        write(path, source.replace(old, new))
        _rail_retention_callback_replaced = True
        return

    recovery_transform_old = '''        let recoveryDisposition = Self.recoveryDisposition(
            isActive: isActive,
            residencyPolicy: residencyPolicy
        )
'''
    if old == recovery_transform_old:
        if _recovery_switch_replaced:
            return
        source = read(path)
        actual_old = '''        switch Self.recoveryDisposition(
            isActive: isActive,
            residencyPolicy: residencyPolicy
        ) {
'''
        actual_new = '''        switch Self.recoveryDisposition(
            isActive: isActive,
            runtimeRetentionPreference: runtimeRetentionPreference
        ) {
'''
        count = source.count(actual_old)
        if count != 1:
            raise SystemExit(
                f"{path}: expected one actual recovery switch, got {count}"
            )
        write(path, source.replace(actual_old, actual_new, 1))
        _recovery_switch_replaced = True
        return

    return _original_replace_once(path, old, new)

'''
text = text.replace(marker, wrapper + marker, 1)

script.write_text(text)
exec(compile(text, str(script), "exec"), {"__name__": "__main__", "__file__": str(script)})
