import AppKit

@MainActor
protocol AppCoordinating: AnyObject {
    func start()
    func handleSecondaryLaunch()
    func prepareForTermination()
}

extension AppCoordinator: AppCoordinating {}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias OwnershipResolver = @MainActor () -> RuntimeInstanceOwnershipResult
    typealias CoordinatorFactory = @MainActor () -> any AppCoordinating
    typealias ActivationRequester = @MainActor () -> Void
    typealias TerminationHandler = @MainActor () -> Void

    private var coordinator: (any AppCoordinating)?
    private var ownershipLease: (any RuntimeInstanceOwnershipLease)?
    private let ownershipResolver: OwnershipResolver
    private let coordinatorFactory: CoordinatorFactory
    private let activationRequester: ActivationRequester
    private let terminationHandler: TerminationHandler
    private let activationController: RuntimeInstanceActivationController

    override convenience init() {
        self.init(
            ownershipResolver: nil,
            coordinatorFactory: nil,
            activationRequester: nil,
            terminationHandler: nil,
            activationObserver: nil
        )
    }

    init(
        ownershipResolver: OwnershipResolver? = nil,
        coordinatorFactory: CoordinatorFactory? = nil,
        activationRequester: ActivationRequester? = nil,
        terminationHandler: TerminationHandler? = nil,
        activationObserver: (any RuntimeInstanceActivationObserving)? = nil
    ) {
        let defaultOwnership = RuntimeInstanceOwnership()
        self.ownershipResolver = ownershipResolver ?? { defaultOwnership.claim() }
        self.coordinatorFactory = coordinatorFactory ?? { AppCoordinator() }
        self.activationRequester = activationRequester
            ?? { DistributedRuntimeInstanceActivationObserver.postActivationRequest() }
        self.terminationHandler = terminationHandler ?? { NSApp.terminate(nil) }
        let observer = activationObserver ?? DistributedRuntimeInstanceActivationObserver()
        self.activationController = RuntimeInstanceActivationController(
            observer: observer,
            activationRequester: self.activationRequester
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activationController.installBootstrapObserver { [weak self] in
            self?.handlePrimaryPresentationRequest()
        }

        switch ownershipResolver() {
        case let .primary(lease):
            ownershipLease = lease
            activationController.markPrimary()
            NSApp.setActivationPolicy(.accessory)

            let coordinator = coordinatorFactory()
            self.coordinator = coordinator
            coordinator.start()
            activationController.markPrimaryReady()

        case .secondary:
            activationController.markSecondary()
            activationController.requestPrimaryPresentation()
            terminationHandler()

        case .ownershipFailure:
            terminationHandler()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handlePrimaryPresentationRequest() {
        coordinator?.handleSecondaryLaunch()
    }
}
