import Foundation
import Combine

// MARK: - AnyCodable (type-erasing Codable wrapper)
struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull() }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}

// MARK: - Hook Event (received from Python script via socket)
struct HookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    var source: String  // "claude" or "codex"

    init(sessionId: String, cwd: String, event: String, status: String, pid: Int?, tty: String?, tool: String?, toolInput: [String: AnyCodable]?, toolUseId: String?, notificationType: String?, message: String?, source: String = "claude") {
        self.sessionId = sessionId
        self.cwd = cwd
        self.event = event
        self.status = status
        self.pid = pid
        self.tty = tty
        self.tool = tool
        self.toolInput = toolInput
        self.toolUseId = toolUseId
        self.notificationType = notificationType
        self.message = message
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, event, status, pid, tty, tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message
        case source
    }

    /// Whether this event expects a response (permission request)
    var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }
}

// MARK: - Hook Response (sent back for permission decisions)
struct HookResponse: Codable {
    let decision: String  // "allow", "deny", or "ask"
    let reason: String?
}

// MARK: - Permission Context
struct PermissionContext: Sendable, Equatable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date

    /// Format tool input for display
    var formattedInput: String? {
        guard let input = toolInput else { return nil }

        // For Bash, show the command
        if toolName == "Bash", let command = input["command"]?.value as? String {
            return command.count > 120 ? String(command.prefix(120)) + "..." : command
        }
        // For Write/Edit, show file path
        if toolName == "Write" || toolName == "Edit", let path = input["file_path"]?.value as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        // For Read, show file path
        if toolName == "Read", let path = input["file_path"]?.value as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        // Priority keys
        let priorityKeys = ["command", "file_path", "path", "query", "pattern", "url"]
        for key in priorityKeys {
            if let value = input[key]?.value as? String {
                return value.count > 120 ? String(value.prefix(120)) + "..." : value
            }
        }
        // Fallback: first non-description string
        for (key, value) in input where key != "description" {
            if let str = value.value as? String {
                return str.count > 120 ? String(str.prefix(120)) + "..." : str
            }
        }
        return nil
    }

    static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
        lhs.toolUseId == rhs.toolUseId && lhs.toolName == rhs.toolName && lhs.receivedAt == rhs.receivedAt
    }
}

// MARK: - Claude Session Phase (state machine)
enum ClaudeSessionPhase: Sendable, Equatable {
    case idle
    case processing
    case waitingForInput
    case waitingForResponse(String?)  // question text
    case waitingForApproval(PermissionContext)
    case compacting
    case error(String)

    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput, .waitingForResponse: return true
        default: return false
        }
    }

    var isWaitingForApproval: Bool {
        if case .waitingForApproval = self { return true }
        return false
    }

    var isNotification: Bool {
        switch self {
        case .waitingForInput, .error, .waitingForResponse: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .processing, .compacting: return true
        default: return false
        }
    }

    static func == (lhs: ClaudeSessionPhase, rhs: ClaudeSessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.waitingForInput, .waitingForInput): return true
        case (.waitingForResponse(let a), .waitingForResponse(let b)): return a == b
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        case (.compacting, .compacting): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Pending Permission (internal tracking)
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
    let source: String  // "claude" or "codex"
}

// MARK: - Session State (internal tracking for sessions)
struct SessionState {
    var phase: ClaudeSessionPhase = .idle
    var sessionId: String? = nil
    var projectName: String? = nil
    var lastToolName: String? = nil
    var toolCount: Int = 0
    var isSubagentActive: Bool = false
    var autoDismissWorkItem: DispatchWorkItem? = nil
}
