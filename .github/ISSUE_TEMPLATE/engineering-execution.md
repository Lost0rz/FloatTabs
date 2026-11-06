---
name: Governed engineering execution (EXECUTION_SPEC_V1)
about: Canonical 19-field Issue contract for approved Engineering Governance work. A created Issue is NOT permission to execute.
title: "[ENGINEERING] "
labels: []
assignees: []
---

> **Pre-approval only.** Delete instructional placeholder text, establish current source evidence, and fully specify deterministic WPs. A trusted approver must post a separate `SPEC_APPROVAL_V1` comment with an exact digest. Labels, this form, Issue authorship, and ChatGPT replies do not grant execution authority. Do not include secrets or private user/runtime logs. The repository's `AGENTS.md` chooses FILE_CONTROL versus ISSUE_CONTROL.

### CONTRACT

EXECUTION_SPEC_V1

### TASK_ID

<stable task identity>

### SPEC_REVISION

1

### MODE

EXECUTE

### PURPOSE

<bounded class>

### OBJECTIVE

<one observable outcome>

### VERIFIED_BASELINE

<fresh repository identity, relevant source/ownership/test evidence>

### TARGET_BEHAVIOR

<positive and negative observable behavior>

### IN_SCOPE

<exact permitted modules/semantics>

### OUT_OF_SCOPE

<explicit exclusions>

### ALLOWED_SIDE_EFFECTS

<exact authorized file/ref/API/data mutations>

### CANONICAL_AUTHORITIES

<AGENTS.md, applicable accepted contract/source locations>

### WORK_PACKAGES

#### WP01 — <concrete bounded action>
Targets: <verified path/symbol/contract>
Preconditions: <verifiable entry conditions>
Actions: <ordered exact edits/checks>
Dependencies: NONE
Edge cases: <failure behavior, limits>
Verification: <command/check and expected evidence>
Done: <checkable outcome>

### VERIFICATION_PLAN

<risk-proportional local tests, CI and identity checks>

### HUMAN_UI_ACCEPTANCE

PENDING

### DEVIATION_POLICY

L0 CONTINUE: verified nonsemantic locator differences only.
L1 LOCAL_CORRECT: bounded approved-scope defects and focused retest only.
L2 PAUSE_AND_ASK: missing architecture/authority, material scope/risk changes or unsafe overlap; post DECISION_REQUEST_V1.
L3 TERMINATE: invalid approval, destructive/unsafe actions or irreconcilable authority.

### STOP_AND_SAFETY

<explicit data safety, unique-work, approval and dependency STOPs>

### RETURN_CONTRACT

Post verified EXECUTION_RECEIPT_V1 or DECISION_REQUEST_V1 to the **same Issue** with actual changed files, PR/ref, CI, human verdict and next action.

### AUTHORIZATION_BASIS

PENDING — no authenticated SPEC_APPROVAL_V1 attached.
