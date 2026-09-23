import Darwin
import Foundation
import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeOwnershipTests: XCTestCase {
    func testFirstProcessClaimsSameLockAndSecondProcessIsNonBlockingSecondary() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockURL = temporaryDirectory.appendingPathComponent("primary.lock")

        let first = RuntimeInstanceOwnership(lockFileURL: lockURL)
        let second = RuntimeInstanceOwnership(lockFileURL: lockURL)

        assertPrimary(first.claim())
        assertSecondary(second.claim())
    }

    func testReleasingPrimaryAllowsNextProcessToClaimWithoutDeletingLockFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockURL = temporaryDirectory.appendingPathComponent("primary.lock")

        var first: RuntimeInstanceOwnership? = RuntimeInstanceOwnership(lockFileURL: lockURL)
        assertPrimary(try XCTUnwrap(first).claim())
        first = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
        assertPrimary(RuntimeInstanceOwnership(lockFileURL: lockURL).claim())
    }

    func testExistingStaleLockFileDoesNotPreventNewPrimary() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockURL = temporaryDirectory.appendingPathComponent("primary.lock")
        XCTAssertTrue(FileManager.default.createFile(atPath: lockURL.path, contents: nil))

        assertPrimary(RuntimeInstanceOwnership(lockFileURL: lockURL).claim())
    }

    func testRuntimeDirectoryAndLockFileUsePrivatePermissions() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let runtimeDirectory = temporaryDirectory.appendingPathComponent("Runtime", isDirectory: true)
        let lockURL = runtimeDirectory.appendingPathComponent("primary.lock")

        assertPrimary(RuntimeInstanceOwnership(lockFileURL: lockURL).claim())

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: runtimeDirectory.path)
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((lockAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDifferentLockPathsCanBothBePrimary() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        assertPrimary(RuntimeInstanceOwnership(
            lockFileURL: temporaryDirectory.appendingPathComponent("one.lock")
        ).claim())
        assertPrimary(RuntimeInstanceOwnership(
            lockFileURL: temporaryDirectory.appendingPathComponent("two.lock")
        ).claim())
    }

    func testRuntimeDirectoryFailureFailsClosed() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let parentFile = temporaryDirectory.appendingPathComponent("not-a-directory")
        XCTAssertTrue(FileManager.default.createFile(atPath: parentFile.path, contents: nil))
        let lockURL = parentFile.appendingPathComponent("Runtime/primary.lock")

        assertOwnershipFailure(RuntimeInstanceOwnership(lockFileURL: lockURL).claim())
    }

    func testOpenFailureFailsClosed() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockURL = temporaryDirectory.appendingPathComponent("primary.lock")
        var openPath: String?
        let operations = RuntimeInstanceLockOperations(
            open: { path, _, _ in
                openPath = String(cString: path)
                return -1
            },
            lock: { _, _ in XCTFail("flock must not run after open failure"); return -1 },
            close: { _ in XCTFail("close must not run without an opened descriptor"); return 0 },
            errorNumber: { Int32(EACCES) }
        )

        assertOwnershipFailure(RuntimeInstanceOwnership(
            lockFileURL: lockURL,
            operations: operations
        ).claim())
        XCTAssertEqual(openPath, lockURL.path)
    }

    func testFlockFailureFailsClosed() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let lockURL = temporaryDirectory.appendingPathComponent("primary.lock")
        XCTAssertTrue(FileManager.default.createFile(atPath: lockURL.path, contents: nil))
        var closedDescriptor: Int32?
        let operations = RuntimeInstanceLockOperations(
            open: { (_: UnsafePointer<CChar>, _: Int32, _: mode_t) in 41 },
            lock: { (_: Int32, _: Int32) in -1 },
            close: { descriptor in
                closedDescriptor = descriptor
                return 0
            },
            errorNumber: { Int32(EPERM) }
        )

        assertOwnershipFailure(RuntimeInstanceOwnership(
            lockFileURL: lockURL,
            operations: operations
        ).claim())
        XCTAssertEqual(closedDescriptor, 41)
    }

    func testPrimaryLaunchCreatesAndStartsCoordinatorExactlyOnceWithoutTerminating() {
        let observer = TestActivationObserver()
        let coordinator = TestCoordinator()
        var claimEvents: [String] = []
        var factoryCount = 0
        var terminationCount = 0
        let appDelegate = AppDelegate(
            ownershipResolver: {
                claimEvents.append("claim")
                return .primary(TestOwnershipLease())
            },
            coordinatorFactory: {
                factoryCount += 1
                return coordinator
            },
            activationRequester: {},
            terminationHandler: { terminationCount += 1 },
            activationObserver: observer
        )
        observer.onInstall = { claimEvents.insert("observer", at: 0) }

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(claimEvents, ["observer", "claim"])
        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(coordinator.startCount, 1)
        XCTAssertEqual(terminationCount, 0)
    }

    func testEarlyActivationRequestsCoalesceAndAreConsumedAfterPrimaryReadyAsExplicitShow() {
        let observer = TestActivationObserver()
        let coordinator = TestCoordinator()
        coordinator.onStart = {
            observer.emit()
            observer.emit()
            observer.emit()
        }
        var terminationCount = 0
        let appDelegate = AppDelegate(
            ownershipResolver: { .primary(TestOwnershipLease()) },
            coordinatorFactory: { coordinator },
            activationRequester: {},
            terminationHandler: { terminationCount += 1 },
            activationObserver: observer
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(coordinator.secondaryLaunchCount, 1)
        XCTAssertEqual(coordinator.toggleCount, 0)
        XCTAssertEqual(terminationCount, 0)

        observer.emit()
        XCTAssertEqual(coordinator.secondaryLaunchCount, 2)
    }

    func testSecondaryLaunchRequestsExplicitPrimaryPresentationAndNeverCreatesCoordinator() {
        let observer = TestActivationObserver()
        let coordinator = TestCoordinator()
        var factoryCount = 0
        var activationRequestCount = 0
        var terminationCount = 0
        let appDelegate = AppDelegate(
            ownershipResolver: { .secondary },
            coordinatorFactory: {
                factoryCount += 1
                return coordinator
            },
            activationRequester: {
                activationRequestCount += 1
                observer.emit()
            },
            terminationHandler: { terminationCount += 1 },
            activationObserver: observer
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(factoryCount, 0)
        XCTAssertEqual(activationRequestCount, 1)
        XCTAssertEqual(coordinator.secondaryLaunchCount, 0)
        XCTAssertEqual(terminationCount, 1)
    }

    func testOwnershipFailureTerminatesWithoutCoordinatorOrActivationRequest() {
        let observer = TestActivationObserver()
        let coordinator = TestCoordinator()
        var factoryCount = 0
        var activationRequestCount = 0
        var terminationCount = 0
        let appDelegate = AppDelegate(
            ownershipResolver: { .ownershipFailure },
            coordinatorFactory: {
                factoryCount += 1
                return coordinator
            },
            activationRequester: { activationRequestCount += 1 },
            terminationHandler: { terminationCount += 1 },
            activationObserver: observer
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(factoryCount, 0)
        XCTAssertEqual(activationRequestCount, 0)
        XCTAssertEqual(terminationCount, 1)
    }

    func testPrimaryDiagnosticsUseOnlyLowSensitivityProcessAndRoleMetadata() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        diagnostics.record(
            event: "app.instance.primary_claimed",
            level: .notice,
            subsystem: "app",
            fields: RuntimeInstanceDiagnosticMetadata.primaryFields(processID: 1234)
        )

        XCTAssertEqual(writer.events.first?.fields["process_id"], .integer(1234))
        XCTAssertEqual(writer.events.first?.fields["instance_role"], .string("primary"))
        XCTAssertFalse(writer.lines.first.map { String(decoding: $0, as: UTF8.self) }?.contains("/") == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabs-runtime-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func assertPrimary(_ result: RuntimeInstanceOwnershipResult, file: StaticString = #filePath, line: UInt = #line) {
        guard case .primary = result else {
            XCTFail("expected primary, got \(result)", file: file, line: line)
            return
        }
    }

    private func assertSecondary(_ result: RuntimeInstanceOwnershipResult, file: StaticString = #filePath, line: UInt = #line) {
        guard case .secondary = result else {
            XCTFail("expected secondary, got \(result)", file: file, line: line)
            return
        }
    }

    private func assertOwnershipFailure(_ result: RuntimeInstanceOwnershipResult, file: StaticString = #filePath, line: UInt = #line) {
        guard case .ownershipFailure = result else {
            XCTFail("expected ownership failure, got \(result)", file: file, line: line)
            return
        }
    }
}

@MainActor
private final class TestOwnershipLease: RuntimeInstanceOwnershipLease {}

@MainActor
private final class TestActivationObserver: RuntimeInstanceActivationObserving {
    private var handler: (() -> Void)?
    var onInstall: (() -> Void)?

    func installBootstrapObserver(_ handler: @escaping () -> Void) {
        onInstall?()
        self.handler = handler
    }

    func emit() {
        handler?()
    }
}

@MainActor
private final class TestCoordinator: AppCoordinating {
    var startCount = 0
    var secondaryLaunchCount = 0
    var toggleCount = 0
    var onStart: (() -> Void)?

    func start() {
        startCount += 1
        onStart?()
    }

    func handleSecondaryLaunch() {
        secondaryLaunchCount += 1
    }

    func prepareForTermination() {}
}
