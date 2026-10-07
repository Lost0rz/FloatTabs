import Darwin
import Foundation

enum MemoXUnixSocketError: Error, Equatable, Sendable {
    case invalidEndpoint
    case system(Int32)
    case deadlineExceeded
    case endOfFile
    case invalidReplyFrame

    var safeCode: String {
        switch self {
        case .invalidEndpoint: "invalid_endpoint"
        case .system: "socket_error"
        case .deadlineExceeded: "timeout"
        case .endOfFile: "unexpected_eof"
        case .invalidReplyFrame: "invalid_reply"
        }
    }
}

/// One bounded request/reply over the sole trusted-local MemoX endpoint.
/// Every connect, partial write, and partial read shares one absolute deadline.
struct MemoXUnixSocketClient: Sendable {
    static let productionTimeout: TimeInterval = 5
    static let maximumReplyBytes = 64 * 1024

    let socketURL: URL
    let timeout: TimeInterval
    let effectiveUID: uid_t

    init(
        socketURL: URL = MemoXActivationStore.defaultReceiverSocketURL,
        timeout: TimeInterval = productionTimeout,
        effectiveUID: uid_t = geteuid()
    ) {
        self.socketURL = socketURL.standardizedFileURL
        self.timeout = timeout
        self.effectiveUID = effectiveUID
    }

    func send(_ envelope: MemoXCaptureEnvelopeV1) throws -> MemoXCaptureReply {
        let frame: Data
        do {
            frame = try envelope.framedRequest()
        } catch {
            throw MemoXUnixSocketError.invalidReplyFrame
        }
        let deadline = Self.deadline(after: timeout)
        let replyJSON = try withConnectedSocket(until: deadline) { descriptor in
            try Self.writeAll(frame, to: descriptor, until: deadline)
            return try Self.readReply(from: descriptor, until: deadline)
        }
        do {
            return try MemoXCaptureReply.parse(data: replyJSON)
        } catch {
            throw MemoXUnixSocketError.invalidReplyFrame
        }
    }

    private func withConnectedSocket<T>(
        until deadline: UInt64,
        operation: (Int32) throws -> T
    ) throws -> T {
        try validateTrustedEndpoint()
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MemoXUnixSocketError.system(errno) }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw MemoXUnixSocketError.system(errno)
        }
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw MemoXUnixSocketError.system(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !pathBytes.isEmpty, pathBytes.count < capacity else {
            throw MemoXUnixSocketError.invalidEndpoint
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw MemoXUnixSocketError.system(errno) }
            try Self.wait(descriptor, events: Int16(POLLOUT), until: deadline)
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
                throw MemoXUnixSocketError.system(errno)
            }
            guard socketError == 0 else { throw MemoXUnixSocketError.system(socketError) }
        }
        return try operation(descriptor)
    }

    private func validateTrustedEndpoint() throws {
        var metadata = stat()
        guard lstat(socketURL.path, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              metadata.st_uid == effectiveUID,
              metadata.st_mode & 0o077 == 0 else {
            throw MemoXUnixSocketError.invalidEndpoint
        }
    }

    private static func deadline(after timeout: TimeInterval) -> UInt64 {
        let seconds = timeout.isFinite ? max(timeout, 0.001) : productionTimeout
        let nanoseconds = UInt64(min(seconds, productionTimeout) * 1_000_000_000)
        return DispatchTime.now().uptimeNanoseconds &+ nanoseconds
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, until deadline: UInt64) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else {
                    throw MemoXUnixSocketError.deadlineExceeded
                }
                let written = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset,
                    0
                )
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0 && errno == EINTR { continue }
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try wait(descriptor, events: Int16(POLLOUT), until: deadline)
                    continue
                }
                throw MemoXUnixSocketError.system(written < 0 ? errno : EIO)
            }
        }
    }

    private static func readReply(from descriptor: Int32, until deadline: UInt64) throws -> Data {
        let header = try readExactly(4, from: descriptor, until: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= UInt32(maximumReplyBytes) else {
            throw MemoXUnixSocketError.invalidReplyFrame
        }
        return try readExactly(Int(length), from: descriptor, until: deadline)
    }

    private static func readExactly(_ count: Int, from descriptor: Int32, until deadline: UInt64) throws -> Data {
        var data = Data(count: count)
        let succeeded = data.withUnsafeMutableBytes { buffer -> Result<Void, MemoXUnixSocketError> in
            guard let baseAddress = buffer.baseAddress else { return .success(()) }
            var offset = 0
            while offset < count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else {
                    return .failure(.deadlineExceeded)
                }
                let readCount = Darwin.recv(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset,
                    0
                )
                if readCount > 0 {
                    offset += readCount
                    continue
                }
                if readCount == 0 { return .failure(.endOfFile) }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    do {
                        try wait(descriptor, events: Int16(POLLIN), until: deadline)
                    } catch let error as MemoXUnixSocketError {
                        return .failure(error)
                    } catch {
                        return .failure(.system(EIO))
                    }
                    continue
                }
                return .failure(.system(errno))
            }
            return .success(())
        }
        try succeeded.get()
        return data
    }

    private static func wait(_ descriptor: Int32, events: Int16, until deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw MemoXUnixSocketError.deadlineExceeded }
            let remaining = deadline - now
            let milliseconds = min(
                Int64(Int32.max),
                max(1, Int64((remaining + 999_999) / 1_000_000))
            )
            var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&pollDescriptor, 1, Int32(milliseconds))
            if result > 0 {
                if pollDescriptor.revents & Int16(POLLNVAL) != 0 {
                    throw MemoXUnixSocketError.system(EBADF)
                }
                return
            }
            if result == 0 { throw MemoXUnixSocketError.deadlineExceeded }
            if errno == EINTR { continue }
            throw MemoXUnixSocketError.system(errno)
        }
    }
}
