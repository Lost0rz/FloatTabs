# FloatTabs Validation Document Status

All Stage-numbered acceptance files and dated pending-fix files in this directory are **historical validation evidence**.

They record what was tested or pending at a specific Stage/commit. They do not authorize current work, define current product truth, or override newer source/tests/contracts.

Use them only to answer historical questions such as:

- what a prior Stage intended to validate;
- what passed/failed at that time;
- which regression or compatibility concern motivated later work.

For current execution, start from `AGENTS.md`, the mode-selected Task/Status (FILE_CONTROL) or exact approved GitHub Issue (ISSUE_CONTROL), `docs/README.md`, and the current linked contract. Re-run or re-establish any old acceptance claim that materially affects current high-risk Runtime work.