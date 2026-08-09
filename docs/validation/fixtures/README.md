# Stage 4 validation fixtures

Serve this directory from the repository root with:

```bash
python3 -m http.server 8765 --directory docs/validation/fixtures
```

Then open one of these URLs in a temporary FloatTabs Slot:

```text
http://127.0.0.1:8765/Stage4NavigationTest.html
http://127.0.0.1:8765/Stage4FileInteractionTest.html
```

The navigation fixture validates same-site `_blank`, external-browser handoff, temporary `window.open`, and popup focus restore.

The file-interaction fixture validates:

- single-file upload;
- multiple-file upload;
- directory upload;
- upload cancellation;
- explicit HTML download (`download.txt`);
- unshowable MIME download (`download.bin`).

The browser may request `favicon.ico` or Apple touch icons and receive 404 responses. Those automatic icon-discovery requests are not validation failures.
