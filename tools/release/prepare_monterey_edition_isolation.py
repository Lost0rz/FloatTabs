#!/usr/bin/env python3
"""Stage 8: Monterey Compatibility Edition identity and storage isolation.

This final build-time transform follows Candidate G and intentionally does not
change WebKit behavior. It only isolates app identity/configuration storage and
adds a raw, one-time legacy WebAppProfiles.json copy.
"""

from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    require_absent,
    require_present,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]
MONTEREY_BUNDLE_ID = "com.lost0rz.FloatTabs.MontereyCompat"
TEST_BUNDLE_ID = "com.lost0rz.FloatTabsTests"
MONTEREY_DISPLAY_NAME = "FloatTabs Monterey"
MONTEREY_SUPPORT_DIRECTORY = "FloatTabs Monterey"
LEGACY_SUPPORT_DIRECTORY = "FloatTabs"
PROFILE_FILE_NAME = "WebAppProfiles.json"


def patch_project_identity() -> None:
    path = ROOT / "FloatTabs.xcodeproj/project.pbxproj"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "PRODUCT_BUNDLE_IDENTIFIER = com.lost0rz.FloatTabs;\n",
        f"PRODUCT_BUNDLE_IDENTIFIER = {MONTEREY_BUNDLE_ID};\n",
        label="MC-B1 application target bundle identifier",
        expected=2,
    )
    text = replace_exact_once(
        text,
        "INFOPLIST_KEY_CFBundleDisplayName = FloatTabs;\n",
        f'INFOPLIST_KEY_CFBundleDisplayName = "{MONTEREY_DISPLAY_NAME}";\n',
        label="MC-B1 application target display name",
        expected=2,
    )
    if text.count(f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_BUNDLE_ID};\n") != 2:
        raise SystemExit("error: MC-B1 test target bundle identifier count changed")
    require_absent(
        text,
        "PRODUCT_BUNDLE_IDENTIFIER = com.lost0rz.FloatTabs;\n",
        label="MC-B1 normal app bundle identifier leaked into generated project",
    )
    write_source(path, text)


STORAGE_DECLARATION = """enum MontereyEditionStorage {
    static let applicationSupportDirectoryName = "FloatTabs Monterey"
    static let legacyApplicationSupportDirectoryName = "FloatTabs"
    static let profileFileName = "WebAppProfiles.json"

    static func configurationURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> URL {
        applicationSupportDirectory(
            fileManager: fileManager,
            override: applicationSupportURL
        )
        .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        .appendingPathComponent(profileFileName, isDirectory: false)
    }

    static func legacyConfigurationURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> URL {
        applicationSupportDirectory(
            fileManager: fileManager,
            override: applicationSupportURL
        )
        .appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        .appendingPathComponent(profileFileName, isDirectory: false)
    }

    /// Copies only the legacy WebAppProfiles.json bytes into Monterey storage.
    /// Explicit ProfileRepository(fileURL:) callers never enter this path.
    @discardableResult
    static func migrateLegacyConfigurationIfNeeded(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> Bool {
        let destinationURL = configurationURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return false
        }

        let legacyURL = legacyConfigurationURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return false
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: legacyURL, to: destinationURL)
        return true
    }

    private static func applicationSupportDirectory(
        fileManager: FileManager,
        override: URL?
    ) -> URL {
        if let override {
            return override
        }
        return (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}

"""


def patch_profile_repository() -> None:
    path = ROOT / "FloatTabs/Persistence/ProfileRepository.swift"
    text = read_source(path)
    text = replace_once_regex(
        text,
        r"^final class ProfileRepository",
        STORAGE_DECLARATION + "final class ProfileRepository",
        label="MC-B1 Monterey storage declaration insertion",
    )

    old_init = """    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

"""
    new_init = """    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            // Explicit repositories own storage selection and never migrate.
            self.fileURL = fileURL
        } else {
            self.fileURL = MontereyEditionStorage.configurationURL(
                fileManager: fileManager
            )
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fileURL == nil {
            do {
                _ = try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager
                )
            } catch {
                NSLog(
                    "[FloatTabs Monterey] legacy configuration migration failed: %@",
                    String(describing: error)
                )
            }
        }
    }

"""
    text = replace_exact_once(
        text,
        old_init,
        new_init,
        label="MC-B1 ProfileRepository default storage and migration seam",
    )

    old_default = """    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("WebAppProfiles.json", isDirectory: false)
    }

"""
    text = replace_exact_once(
        text,
        old_default,
        "",
        label="MC-B1 normal default profile path removal",
    )
    write_source(path, text)


IDENTITY_AND_MIGRATION_TESTS = r'''    func testMontereyEditionStorageUsesSeparateProfileNamespace() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMCB1Paths-\(UUID().uuidString)", isDirectory: true)
        let legacy = MontereyEditionStorage.legacyConfigurationURL(
            applicationSupportURL: root
        )
        let monterey = MontereyEditionStorage.configurationURL(
            applicationSupportURL: root
        )

        XCTAssertEqual(legacy.lastPathComponent, "WebAppProfiles.json")
        XCTAssertEqual(monterey.lastPathComponent, "WebAppProfiles.json")
        XCTAssertEqual(legacy.deletingLastPathComponent().lastPathComponent, "FloatTabs")
        XCTAssertEqual(
            monterey.deletingLastPathComponent().lastPathComponent,
            "FloatTabs Monterey"
        )
        XCTAssertNotEqual(legacy, monterey)
    }

    func testMontereyBundleIdentityAndDisplayName() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "com.lost0rz.FloatTabs.MontereyCompat"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            "FloatTabs Monterey"
        )
    }

    func testLegacyConfigurationIsCopiedByteForByteWhenMontereyIsAbsent() throws {
        try withMontereyStorage { fileManager, root in
            let legacy = MontereyEditionStorage.legacyConfigurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let destination = MontereyEditionStorage.configurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let original = Data("{ legacy: exact-bytes }\n".utf8)
            try fileManager.createDirectory(
                at: legacy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try original.write(to: legacy)

            XCTAssertTrue(
                try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager,
                    applicationSupportURL: root
                )
            )
            XCTAssertEqual(try Data(contentsOf: destination), original)
            XCTAssertEqual(try Data(contentsOf: legacy), original)
        }
    }

    func testExistingMontereyConfigurationWinsWithoutImportOrOverwrite() throws {
        try withMontereyStorage { fileManager, root in
            let legacy = MontereyEditionStorage.legacyConfigurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let destination = MontereyEditionStorage.configurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let legacyBytes = Data("legacy\n".utf8)
            let montereyBytes = Data("monterey\n".utf8)
            try fileManager.createDirectory(
                at: legacy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try legacyBytes.write(to: legacy)
            try montereyBytes.write(to: destination)

            XCTAssertFalse(
                try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager,
                    applicationSupportURL: root
                )
            )
            XCTAssertEqual(try Data(contentsOf: legacy), legacyBytes)
            XCTAssertEqual(try Data(contentsOf: destination), montereyBytes)
        }
    }

    func testMigrationCheckDoesNotCreateStorageWhenBothFilesAreAbsent() throws {
        try withMontereyStorage { fileManager, root in
            XCTAssertFalse(
                try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager,
                    applicationSupportURL: root
                )
            )
            XCTAssertFalse(
                fileManager.fileExists(
                    atPath: root.appendingPathComponent("FloatTabs Monterey").path
                )
            )
            XCTAssertFalse(
                fileManager.fileExists(
                    atPath: root.appendingPathComponent("FloatTabs").path
                )
            )
        }
    }

    func testCorruptLegacyConfigurationIsCopiedRawBeforeRepositoryRecovery() throws {
        try withMontereyStorage { fileManager, root in
            let legacy = MontereyEditionStorage.legacyConfigurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let destination = MontereyEditionStorage.configurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let corrupt = Data("{ corrupt legacy bytes".utf8)
            try fileManager.createDirectory(
                at: legacy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try corrupt.write(to: legacy)

            XCTAssertTrue(
                try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager,
                    applicationSupportURL: root
                )
            )
            XCTAssertEqual(try Data(contentsOf: destination), corrupt)
            XCTAssertEqual(try Data(contentsOf: legacy), corrupt)

            let repository = ProfileRepository(fileManager: fileManager, fileURL: destination)
            XCTAssertThrowsError(try repository.load())
            XCTAssertTrue(repository.startupRecoveryRequired)
            XCTAssertEqual(try Data(contentsOf: legacy), corrupt)
        }
    }

    func testExplicitFileURLDoesNotTriggerAutomaticLegacyMigration() throws {
        try withMontereyStorage { fileManager, root in
            let legacy = MontereyEditionStorage.legacyConfigurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let custom = root
                .appendingPathComponent("Custom", isDirectory: true)
                .appendingPathComponent("WebAppProfiles.json")
            try fileManager.createDirectory(
                at: legacy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("legacy\n".utf8).write(to: legacy)

            let repository = ProfileRepository(fileManager: fileManager, fileURL: custom)
            XCTAssertEqual(try repository.load(), .empty)
            XCTAssertFalse(
                fileManager.fileExists(
                    atPath: root.appendingPathComponent("FloatTabs Monterey/WebAppProfiles.json").path
                )
            )
        }
    }

    func testMontereySaveChangesOnlyTheMontereyConfigurationAfterMigration() throws {
        try withMontereyStorage { fileManager, root in
            let legacy = MontereyEditionStorage.legacyConfigurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let destination = MontereyEditionStorage.configurationURL(
                fileManager: fileManager,
                applicationSupportURL: root
            )
            let legacyBytes = Data("legacy exact bytes\n".utf8)
            try fileManager.createDirectory(
                at: legacy.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try legacyBytes.write(to: legacy)
            XCTAssertTrue(
                try MontereyEditionStorage.migrateLegacyConfigurationIfNeeded(
                    fileManager: fileManager,
                    applicationSupportURL: root
                )
            )

            let repository = ProfileRepository(fileManager: fileManager, fileURL: destination)
            try repository.save(.empty)

            XCTAssertEqual(try Data(contentsOf: legacy), legacyBytes)
            XCTAssertNotEqual(try Data(contentsOf: destination), legacyBytes)
        }
    }
'''


def patch_generated_tests() -> None:
    path = ROOT / "FloatTabsTests/ProfileRepositoryTests.swift"
    text = read_source(path)
    text = replace_once_regex(
        text,
        r"^    private func withRepository\(",
        IDENTITY_AND_MIGRATION_TESTS + "    private func withRepository(",
        label="MC-B1 identity and migration tests",
    )
    old_helper = """    private func withRepository(
        _ body: (ProfileRepository, URL) throws -> Void
    ) throws {
"""
    new_helper = """    private func withMontereyStorage(
        _ body: (FileManager, URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabsMCB1Storage-\\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try body(fileManager, root)
    }

    private func withRepository(
        _ body: (ProfileRepository, URL) throws -> Void
    ) throws {
"""
    text = replace_exact_once(
        text,
        old_helper,
        new_helper,
        label="MC-B1 temporary storage test helper",
    )
    write_source(path, text)


def verify_contract() -> None:
    project = read_source(ROOT / "FloatTabs.xcodeproj/project.pbxproj")
    profile = read_source(ROOT / "FloatTabs/Persistence/ProfileRepository.swift")
    tests = read_source(ROOT / "FloatTabsTests/ProfileRepositoryTests.swift")
    build_script = read_source(ROOT / "tools/release/build_monterey_dmg.sh")

    require_present(
        project,
        f"PRODUCT_BUNDLE_IDENTIFIER = {MONTEREY_BUNDLE_ID};",
        label="MC-B1 generated app bundle ID",
    )
    require_present(
        project,
        f'INFOPLIST_KEY_CFBundleDisplayName = "{MONTEREY_DISPLAY_NAME}";',
        label="MC-B1 generated display name",
    )
    if project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {MONTEREY_BUNDLE_ID};") != 2:
        raise SystemExit("error: MC-B1 generated app bundle ID count is not 2")
    if project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {TEST_BUNDLE_ID};") != 2:
        raise SystemExit("error: MC-B1 generated test bundle ID count is not 2")
    require_absent(
        project,
        "PRODUCT_BUNDLE_IDENTIFIER = com.lost0rz.FloatTabs;",
        label="MC-B1 normal app bundle ID survived",
    )

    for marker in [
        "enum MontereyEditionStorage",
        'static let applicationSupportDirectoryName = "FloatTabs Monterey"',
        'static let legacyApplicationSupportDirectoryName = "FloatTabs"',
        'static let profileFileName = "WebAppProfiles.json"',
        "static func configurationURL(",
        "static func legacyConfigurationURL(",
        "static func migrateLegacyConfigurationIfNeeded(",
        "try fileManager.copyItem(at: legacyURL, to: destinationURL)",
        "self.fileURL = MontereyEditionStorage.configurationURL(",
        "if fileURL == nil",
    ]:
        require_present(profile, marker, label=f"MC-B1 storage marker: {marker}")
    for forbidden in [
        "moveItem",
        "removeItem(at: legacyURL",
        "WKWebsiteDataStore(forIdentifier:",
        "removeData(",
        "fetchDataRecords",
        "allWebsiteDataTypes",
        "HTTPCookieStorage",
        "WKHTTPCookieStore",
    ]:
        require_absent(profile, forbidden, label=f"MC-B1 forbidden migration API: {forbidden}")

    for marker in [
        "testMontereyEditionStorageUsesSeparateProfileNamespace",
        "testMontereyBundleIdentityAndDisplayName",
        "testLegacyConfigurationIsCopiedByteForByteWhenMontereyIsAbsent",
        "testExistingMontereyConfigurationWinsWithoutImportOrOverwrite",
        "testMigrationCheckDoesNotCreateStorageWhenBothFilesAreAbsent",
        "testCorruptLegacyConfigurationIsCopiedRawBeforeRepositoryRecovery",
        "testExplicitFileURLDoesNotTriggerAutomaticLegacyMigration",
        "testMontereySaveChangesOnlyTheMontereyConfigurationAfterMigration",
    ]:
        require_present(tests, marker, label=f"MC-B1 generated test: {marker}")

    require_present(
        build_script,
        "python3 tools/release/prepare_monterey_candidate_g.py\n"
        "python3 tools/release/prepare_monterey_edition_isolation.py\n",
        label="MC-B1 build transform ordering",
    )
    require_absent(
        build_script,
        "prepare_monterey_candidate_h.py",
        label="Candidate H transform leaked into MC-B1 build",
    )

    generated_swift = "\n".join(
        path.read_text(encoding="utf-8")
        for directory in (ROOT / "FloatTabs", ROOT / "FloatTabsTests")
        for path in sorted(directory.rglob("*.swift"))
    )
    for forbidden in [
        "MontereySafariIdentityDiagnostic",
        "FLOATTABS_MONTEREY_H_MODE",
        "WKWebsiteDataStore(forIdentifier:",
        "removeData(",
        "fetchDataRecords",
        "allWebsiteDataTypes",
        "HTTPCookieStorage",
        "WKHTTPCookieStore",
    ]:
        require_absent(
            generated_swift,
            forbidden,
            label=f"MC-B1 forbidden generated source content: {forbidden}",
        )

    webview_factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    observer = read_source(ROOT / "FloatTabs/Web/SlotNavigationObserver.swift")
    require_present(
        webview_factory,
        "configuration.websiteDataStore = .default()",
        label="MC-B1 default WKWebsiteDataStore contract",
    )
    require_present(
        popup,
        "let popupWebView = WKWebView(\n            frame: .zero,\n            configuration: configuration\n        )",
        label="MC-B1 callback popup construction",
    )
    require_present(
        observer,
        "webView.navigationDelegate = self",
        label="MC-B1 Candidate G primary navigation delegate",
    )
    require_absent(
        popup,
        "popupWebView.navigationDelegate =",
        label="MC-B1 popup navigation delegate assignment",
    )


def main() -> None:
    patch_project_identity()
    patch_profile_repository()
    patch_generated_tests()
    verify_contract()
    print("Applied Monterey Compatibility Edition identity and storage isolation.")


if __name__ == "__main__":
    main()
