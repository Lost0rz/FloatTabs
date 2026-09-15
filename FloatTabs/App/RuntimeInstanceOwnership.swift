import Darwin
import Foundation
import OSLog

protocol RuntimeInstanceOwnershipLease: AnyObject {}

enum RuntimeInstanceOwnershipResult {
    case primary(any RuntimeInstanceOwnershipLease)
    case secondary
    case ownershipFailure
}

struct RuntimeInstanceLockOperations: @unchecked Sendable {
    let open: (UnsafePointer<CChar>, Int32, mode_t) -> Int32
    let lock: (Int32, Int32) -> Int32
    let close: (Int32) -> Int32
    let errorNumber: () -> Int32

    init(
        open: @escaping (UnsafePointer<CChar>, Int32, mode_t) -> Int32,
        lock: @escaping (Int32, Int32) -> Int32,
        close: @escaping (Int32) -> Int32,
        errorNumber: @escaping () -> Int32
    ) {
        self.open = open
        self.lock = lock
        self.close = close
        self.errorNumber = errorNumber
    }

    static let system = Self(
        open: { path, flags, mode in Darwin.open(path, flags, mode) },
        lock: { descriptor, operation in flock(descriptor, operation) },
        close: { descriptor in Darwin.close(descriptor) },
        errorNumber: { Darwin.errno }
    )
}

/// Owns the process-wide runtime lock for the lifetime of the primary app.
/// The lock file is intentionally never removed: the descriptor, not file
/// existence or PID metadata, is the authority.
@MainActor
final class RuntimeInstanceOwnership: RuntimeInstanceOwnershipLease {
    private static let logger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "RuntimeInstanceOwnership"
    )

    static var defaultLockFileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("primary.lock", isDirectory: false)
    }

    private let lockFileURL: URL
    private let fileManager: FileManager
    private let operations: RuntimeInstanceLockOperations
    private var descriptor: Int32 = -1
    private var attemptedRole: AttemptedRole?

    private enum AttemptedRole {
        case primary
        case secondary
        case ownershipFailure
    }

    init(
        lockFileURL: URL = RuntimeInstanceOwnership.defaultLockFileURL,
        fileManager: FileManager = .default,
        operations: RuntimeInstanceLockOperations = .system
    ) {
        self.lockFileURL = lockFileURL
        self.fileManager = fileManager
        self.operations = operations
    }

    func claim() -> RuntimeInstanceOwnershipResult {
        if let attemptedRole {
            switch attemptedRole {
            case .primary:
                return .primary(self)
            case .secondary:
                return .secondary
            case .ownershipFailure:
                return .ownershipFailure
            }
        }

        let runtimeDirectory = lockFileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: runtimeDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: UInt16(0o700))]
            )
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: UInt16(0o700))],
                ofItemAtPath: runtimeDirectory.path
            )
        } catch {
            return failClosed("runtime directory unavailable")
        }

        let openedDescriptor = lockFileURL.path.withCString { path in
            operations.open(path, O_RDWR | O_CREAT, mode_t(0o600))
        }
        guard openedDescriptor >= 0 else {
            return failClosed("lock file open failed")
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: UInt16(0o600))],
                ofItemAtPath: lockFileURL.path
            )
        } catch {
            _ = operations.close(openedDescriptor)
            return failClosed("lock file permissions unavailable")
        }

        let lockResult = operations.lock(openedDescriptor, LOCK_EX | LOCK_NB)
        guard lockResult == 0 else {
            let errorNumber = operations.errorNumber()
            _ = operations.close(openedDescriptor)
            if errorNumber == EWOULDBLOCK || errorNumber == EAGAIN {
                attemptedRole = .secondary
                log("secondary launch observed", role: "secondary")
                return .secondary
            }
            return failClosed("lock acquisition failed")
        }

        descriptor = openedDescriptor
        attemptedRole = .primary
        log("primary lock claimed", role: "primary")
        return .primary(self)
    }

    deinit {
        if descriptor >= 0 {
            _ = operations.close(descriptor)
        }
    }

    private func failClosed(_ reason: String) -> RuntimeInstanceOwnershipResult {
        attemptedRole = .ownershipFailure
        log(reason, role: "ownership_failure")
        return .ownershipFailure
    }

    private func log(_ message: String, role: String) {
        if role == "ownership_failure" {
            Self.logger.error("\(message, privacy: .public) process_id=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) instance_role=\(role, privacy: .public)")
        } else {
            Self.logger.notice("\(message, privacy: .public) process_id=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) instance_role=\(role, privacy: .public)")
        }
    }
}

enum RuntimeInstanceDiagnosticMetadata {
    static func primaryFields(
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> [String: RuntimeDiagnosticValue] {
        [
            "process_id": .integer(Int64(processID)),
            "instance_role": .string("primary")
        ]
    }
}

@MainActor
protocol RuntimeInstanceActivationObserving: AnyObject {
    func installBootstrapObserver(_ handler: @escaping () -> Void)
}

@MainActor
final class DistributedRuntimeInstanceActivationObserver: RuntimeInstanceActivationObserving {
    static let notificationName = Notification.Name(
        "com.lost0rz.FloatTabs.instance-activate.v1"
    )

    private var observer: NSObjectProtocol?
    private let notificationCenter: DistributedNotificationCenter

    init(notificationCenter: DistributedNotificationCenter = .default()) {
        self.notificationCenter = notificationCenter
    }

    func installBootstrapObserver(_ handler: @escaping () -> Void) {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = notificationCenter.addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    static func postActivationRequest() {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }
}

/// Coalesces activation requests received while the primary coordinator is
/// still being constructed. Secondary broadcasts are ignored by a process that
/// has already determined it is secondary.
@MainActor
final class RuntimeInstanceActivationController {
    private enum Role {
        case undecided
        case primary
        case secondary
    }

    private let observer: any RuntimeInstanceActivationObserving
    private let activationRequester: () -> Void
    private var role: Role = .undecided
    private var primaryReady = false
    private var pendingPresentationRequest = false
    private var onPresentationRequested: (() -> Void)?

    init(
        observer: any RuntimeInstanceActivationObserving,
        activationRequester: @escaping () -> Void
    ) {
        self.observer = observer
        self.activationRequester = activationRequester
    }

    func installBootstrapObserver(onPresentationRequested: @escaping () -> Void) {
        self.onPresentationRequested = onPresentationRequested
        observer.installBootstrapObserver { [weak self] in
            self?.receiveActivationRequest()
        }
    }

    func markPrimary() {
        role = .primary
    }

    func markSecondary() {
        role = .secondary
        primaryReady = false
        pendingPresentationRequest = false
    }

    func markPrimaryReady() {
        guard role == .primary else { return }
        primaryReady = true
        consumePendingPresentationRequestIfNeeded()
    }

    func requestPrimaryPresentation() {
        activationRequester()
    }

    private func receiveActivationRequest() {
        guard role != .secondary else { return }
        guard primaryReady else {
            pendingPresentationRequest = true
            return
        }
        onPresentationRequested?()
    }

    private func consumePendingPresentationRequestIfNeeded() {
        guard pendingPresentationRequest else { return }
        pendingPresentationRequest = false
        onPresentationRequested?()
    }
}
