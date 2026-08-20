# FloatTabs v0.1.3 Build 5 correction trigger

This temporary marker opens the observable one-shot PR trigger for the validated Settings version/build correction.

Expected runner sequence:
1. Apply the Settings About/version/latest-fixes patch.
2. Bump build 4 to build 5 while keeping marketing version 0.1.3.
3. Run XCTest.
4. Build and verify the Universal 2 DMG/dSYM package.
5. Commit the validated product patch to main and remove this marker plus the temporary runner.
6. Replace the existing v0.1.3 release assets/tag in place.
