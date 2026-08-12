#if DEBUG
import Darwin
import Foundation

/// Debug-only loopback control channel for the local benchmark harness.
///
/// The listener binds to 127.0.0.1 on an ephemeral port and requires a random
/// per-process token written to the user's FloatTabs Application Support folder.
/// Release builds contain no benchmark listener or control-info publication.
final class BenchmarkControlServer: @unchecked Sendable {
    static let protocolVersion = 1

    private let token = UUID().uuidString
    private let commandHandler: @MainActor @Sendable ([String: Any]) -> [String: Any]
    private let acceptQueue = DispatchQueue(label: "com.lost0rz.FloatTabs.benchmark-control")
    private let stateLock = NSLock()
    private var listenerFD: Int32 = -1
    private var controlInfoURL: URL?

    init(commandHandler: @escaping @MainActor @Sendable ([String: Any]) -> [String: Any]) {
        self.commandHandler = commandHandler
    }

    func start() throws {
        guard stateLock.withLock({ listenerFD < 0 }) else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(fd, socketAddress, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }

        let port = UInt16(bigEndian: boundAddress.sin_port)
        do {
            try publishControlInfo(port: port)
        } catch {
            Darwin.close(fd)
            throw error
        }
        stateLock.withLock {
            listenerFD = fd
        }

        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenerFD: fd)
        }
    }

    func stop() {
        let (fd, infoURL) = stateLock.withLock {
            let values = (listenerFD, controlInfoURL)
            listenerFD = -1
            controlInfoURL = nil
            return values
        }
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        if let infoURL {
            try? FileManager.default.removeItem(at: infoURL)
        }
    }

    deinit {
        stop()
    }

    private func publishControlInfo(port: UInt16) throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("FloatTabs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("BenchmarkControl.json", isDirectory: false)
        let payload: [String: Any] = [
            "protocol_version": Self.protocolVersion,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "host": "127.0.0.1",
            "port": Int(port),
            "token": token,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        stateLock.withLock {
            controlInfoURL = url
        }
    }

    private func acceptLoop(listenerFD: Int32) {
        while isCurrentListener(listenerFD) {
            let connectionFD = Darwin.accept(listenerFD, nil, nil)
            if connectionFD < 0 {
                if !isCurrentListener(listenerFD) { return }
                continue
            }
            handleConnection(connectionFD)
        }
    }

    private func isCurrentListener(_ fd: Int32) -> Bool {
        stateLock.withLock { listenerFD == fd }
    }

    private func handleConnection(_ fd: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count < 64 * 1024 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(fd, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
            if data.last == 0x0A { break }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let request = object as? [String: Any] else {
            writeResponse(["ok": false, "error": "invalid_json"], to: fd)
            return
        }
        guard request["token"] as? String == token else {
            writeResponse(["ok": false, "error": "unauthorized"], to: fd)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                Darwin.close(fd)
                return
            }
            let response = self.commandHandler(request)
            self.writeResponse(response, to: fd)
        }
    }

    private func writeResponse(_ response: [String: Any], to fd: Int32) {
        var payload = response
        if payload["ok"] == nil {
            payload["ok"] = true
        }
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            Darwin.close(fd)
            return
        }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            _ = Darwin.write(fd, baseAddress, bytes.count)
        }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}
#endif
