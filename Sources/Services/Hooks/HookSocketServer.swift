import Foundation
import Combine

/// Unix domain socket server that receives hook events from the Python script.
/// Uses GCD DispatchSource for non-blocking I/O.
final class HookSocketServer: @unchecked Sendable {
    static let shared = HookSocketServer()

    // MARK: - Constants
    private static let socketPath = "/tmp/vibe-pomodoro-claude.sock"
    private static let bufferSize = 16_384  // 16KB read buffer (events are typically 1-2KB)
    private static let pollTimeout: TimeInterval = 0.5

    // MARK: - Publishers
    let eventSubject = PassthroughSubject<HookEvent, Never>()

    // MARK: - State
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let socketQueue = DispatchQueue(label: "com.vibepomodoro.socket", qos: .userInitiated)
    private let lock = NSLock()
    private var pendingPermissions: [String: PendingPermission] = [:]  // keyed by toolUseId
    private var pendingQuestions: [String: PendingQuestion] = [:]  // keyed by toolUseId
    private var isRunning = false

    // MARK: - FIFO Cache for tool_use_id correlation (PreToolUse -> PermissionRequest)
    private struct ToolUseEntry {
        let toolUseId: String
        let toolName: String
        let toolInput: [String: AnyCodable]?
        let timestamp: Date
    }
    private var toolUseCache: [ToolUseEntry] = []
    private let maxCacheSize = 50

    private init() {}

    // MARK: - Public API

    func start() {
        socketQueue.async { [weak self] in
            self?.startServer()
        }
    }

    func stop() {
        socketQueue.async { [weak self] in
            self?.stopServer()
        }
    }

    /// Send a permission response back to the hook script
    func respondToPermission(toolUseId: String, decision: String, reason: String?, updatedPermissions: [[String: AnyCodable]]? = nil) {
        lock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        let response = HookResponse(decision: decision, reason: reason, updatedPermissions: updatedPermissions)
        socketQueue.async {
            self.sendResponse(response, to: pending.clientSocket)
        }
    }

    /// Send a question response back to the hook script
    func respondToQuestion(toolUseId: String, answers: [String: String]) {
        lock.lock()
        guard let pending = pendingQuestions.removeValue(forKey: toolUseId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        let response = QuestionResponse(answers: answers)
        socketQueue.async {
            self.sendQuestionResponse(response, to: pending.clientSocket)
        }
    }

    /// Get current pending permissions count
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingPermissions.count
    }

    /// Get current pending questions count
    var pendingQuestionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingQuestions.count
    }

    // MARK: - Server Lifecycle

    private func startServer() {
        guard !isRunning else { return }

        // Clean up any existing socket file
        unlink(Self.socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[HookSocketServer] Failed to create socket: \(errno)")
            return
        }

        // Set non-blocking
        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                raw.copyMemory(from: cstr, byteCount: strlen(cstr) + 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[HookSocketServer] Failed to bind: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Set permissions (chmod 600)
        chmod(Self.socketPath, 0o600)

        // Listen
        guard listen(serverSocket, 16) == 0 else {
            print("[HookSocketServer] Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            unlink(Self.socketPath)
            return
        }

        // Create accept dispatch source
        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.serverSocket >= 0 {
                close(self.serverSocket)
                self.serverSocket = -1
            }
            unlink(Self.socketPath)
        }
        source.resume()
        acceptSource = source
        isRunning = true
        print("[HookSocketServer] Listening on \(Self.socketPath)")
        startPendingSweep()
    }

    private func stopServer() {
        guard isRunning else { return }
        isRunning = false

        acceptSource?.cancel()
        acceptSource = nil

        // Close all pending permission and question sockets
        lock.lock()
        let pending = pendingPermissions
        pendingPermissions.removeAll()
        let pendingQ = pendingQuestions
        pendingQuestions.removeAll()
        lock.unlock()

        for (_, perm) in pending {
            close(perm.clientSocket)
        }
        for (_, q) in pendingQ {
            close(q.clientSocket)
        }

        // Socket cleanup happens in cancel handler
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(Self.socketPath)
        print("[HookSocketServer] Stopped")
    }

    // MARK: - Connection Handling

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverSocket, sockPtr, &addrLen)
            }
        }

        guard clientFd >= 0 else { return }

        // Set SO_NOSIGPIPE on client socket
        var nosigpipe: Int32 = 1
        setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Set client socket to non-blocking (inherited from listening socket on macOS)
        let clientFlags = fcntl(clientFd, F_GETFL)
        _ = fcntl(clientFd, F_SETFL, clientFlags | O_NONBLOCK)

        // Handle client in background
        socketQueue.async { [weak self] in
            self?.handleClient(fd: clientFd)
        }
    }

    private func handleClient(fd: Int32) {
        defer {
            // Only close if not kept open for permission response
            if !isSocketPendingPermission(fd) {
                close(fd)
            }
        }

        // Read data with poll timeout
        var buffer = [UInt8](repeating: 0, count: Self.bufferSize)
        var data = Data()
        let deadline = Date().addingTimeInterval(Self.pollTimeout)

        while Date() < deadline {
            let bytesRead = read(fd, &buffer, Self.bufferSize)
            if bytesRead > 0 {
                data.append(contentsOf: buffer[0..<bytesRead])
                // Check if we got a complete JSON (simple heuristic: ends with })
                if let lastByte = data.last, lastByte == UInt8(ascii: "}") {
                    break
                }
            } else if bytesRead == 0 {
                break  // Connection closed
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(10_000)  // 10ms sleep before retry
                continue
            } else {
                break  // Error
            }
        }

        guard !data.isEmpty else { return }

        // Parse event
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            print("[HookSocketServer] Failed to decode event from \(data.count) bytes")
            return
        }

        // Cache tool_use_id from PreToolUse for correlation
        if event.event == "PreToolUse", let toolUseId = event.toolUseId {
            cacheToolUse(toolUseId: toolUseId, toolName: event.tool ?? "unknown", toolInput: event.toolInput)
        }

        // Handle permission requests and questions specially - keep socket open
        if event.expectsResponse {
            let toolUseId = event.toolUseId ?? resolveToolUseId(for: event) ?? UUID().uuidString

            if event.status == "asking_question" {
                // Question event — store in pendingQuestions
                let pending = PendingQuestion(
                    sessionId: event.sessionId,
                    toolUseId: toolUseId,
                    clientSocket: fd,
                    event: event,
                    receivedAt: Date(),
                    source: event.source
                )
                lock.lock()
                if let existing = pendingQuestions[toolUseId] {
                    close(existing.clientSocket)
                }
                pendingQuestions[toolUseId] = pending
                lock.unlock()
            } else {
                // Permission request
                let pending = PendingPermission(
                    sessionId: event.sessionId,
                    toolUseId: toolUseId,
                    clientSocket: fd,
                    event: event,
                    receivedAt: Date(),
                    source: event.source
                )
                lock.lock()
                if let existing = pendingPermissions[toolUseId] {
                    close(existing.clientSocket)
                }
                pendingPermissions[toolUseId] = pending
                lock.unlock()
            }

            // Emit event with resolved toolUseId so the manager uses the same key
            let resolvedEvent = HookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,
                notificationType: event.notificationType,
                message: event.message,
                source: event.source,
                permissionSuggestions: event.permissionSuggestions
            )
            eventSubject.send(resolvedEvent)
        } else {
            eventSubject.send(event)
        }
    }

    // MARK: - Response

    private func sendResponse(_ response: HookResponse, to fd: Int32) {
        guard let data = try? JSONEncoder().encode(response) else {
            close(fd)
            return
        }
        writeAndClose(data: data, fd: fd)
    }

    private func sendQuestionResponse(_ response: QuestionResponse, to fd: Int32) {
        guard let data = try? JSONEncoder().encode(response) else {
            close(fd)
            return
        }
        writeAndClose(data: data, fd: fd)
    }

    private func writeAndClose(data: Data, fd: Int32) {
        data.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else { return }
            var remaining = data.count
            var ptr = baseAddress
            while remaining > 0 {
                let written = write(fd, ptr, remaining)
                if written <= 0 { break }
                remaining -= written
                ptr = ptr.advanced(by: written)
            }
        }
        close(fd)
    }

    // MARK: - Stale Permission Sweeping

    private func sweepStalePermissions() {
        lock.lock()
        let now = Date()
        let stalePerms = pendingPermissions.filter { now.timeIntervalSince($0.value.receivedAt) > 310 }
        for (key, _) in stalePerms {
            pendingPermissions.removeValue(forKey: key)
        }
        let staleQuestions = pendingQuestions.filter { now.timeIntervalSince($0.value.receivedAt) > 310 }
        for (key, _) in staleQuestions {
            pendingQuestions.removeValue(forKey: key)
        }
        lock.unlock()

        for (_, perm) in stalePerms {
            close(perm.clientSocket)
        }
        for (_, q) in staleQuestions {
            close(q.clientSocket)
        }
    }

    private func startPendingSweep() {
        socketQueue.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.sweepStalePermissions()
            self?.startPendingSweep()
        }
    }

    // MARK: - Helpers

    private func isSocketPendingPermission(_ fd: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingPermissions.values.contains { $0.clientSocket == fd } ||
               pendingQuestions.values.contains { $0.clientSocket == fd }
    }

    // MARK: - FIFO Cache

    private func cacheToolUse(toolUseId: String, toolName: String, toolInput: [String: AnyCodable]?) {
        lock.lock()
        defer { lock.unlock() }
        let entry = ToolUseEntry(toolUseId: toolUseId, toolName: toolName, toolInput: toolInput, timestamp: Date())
        toolUseCache.append(entry)
        if toolUseCache.count > maxCacheSize {
            toolUseCache.removeFirst()
        }
    }

    private func resolveToolUseId(for event: HookEvent) -> String? {
        lock.lock()
        defer { lock.unlock() }
        // Find the most recent PreToolUse with matching tool name
        guard let toolName = event.tool else { return nil }
        return toolUseCache.last(where: { $0.toolName == toolName && Date().timeIntervalSince($0.timestamp) < 60 })?.toolUseId
    }
}
