import Foundation

/// 番茄钟状态枚举
enum PomodoroStatus: String, Codable {
    case idle = "idle"           // 空闲
    case working = "working"     // 工作中
    case shortBreak = "shortBreak"  // 短休息
    case longBreak = "longBreak"    // 长休息
    case paused = "paused"       // 已暂停
}

/// 番茄钟配置
struct PomodoroConfig: Codable {
    var workDuration: Int = 25 * 60      // 工作时长（秒）：25分钟
    var shortBreakDuration: Int = 5 * 60  // 短休息时长：5分钟
    var longBreakDuration: Int = 15 * 60  // 长休息时长：15分钟
    var roundsBeforeLongBreak: Int = 4    // 长休息前的轮数
    var autoStartBreak: Bool = false      // 自动开始休息
    var autoStartWork: Bool = false       // 自动开始工作
    var selectedDisplayNames: [String] = [] // 选中的显示器名称（空 = 仅内建屏幕）
    var notchGapWidth: Int = 240             // 刘海占位区域宽度（pt）
    var compactWidth: Int = 400    // 收起状态窗口宽度（pt）
    var expandedWidth: Int = 360   // 展开状态窗口宽度（pt）
    var compactLayout: CompactLayoutConfig = .default
    
    static let `default` = PomodoroConfig()
}

// MARK: - Compact Layout Configuration

struct CompactLayoutConfig: Codable, Equatable {
    var elements: [CompactElement] = CompactElement.defaultOrder
    
    static let `default` = CompactLayoutConfig()
}

struct CompactElement: Codable, Identifiable, Equatable {
    let id: String           // "progressRing", "statusLabel", "timer", "aiIndicator"
    var isVisible: Bool = true
    var fontSize: Int = 0    // 0 = use default; otherwise override
    var wing: Wing = .left
    var order: Int = 0
    
    enum Wing: String, Codable {
        case left, right
    }
    
    /// User-facing display name
    var displayName: String {
        switch id {
        case "progressRing": return "进度环"
        case "statusLabel": return "状态文字"
        case "timer": return "倒计时"
        case "aiIndicator": return "AI 指示灯"
        default: return id
        }
    }
    
    static let defaultOrder: [CompactElement] = [
        CompactElement(id: "progressRing", isVisible: true, fontSize: 0, wing: .left, order: 0),
        CompactElement(id: "statusLabel", isVisible: true, fontSize: 0, wing: .left, order: 1),
        CompactElement(id: "timer", isVisible: true, fontSize: 0, wing: .left, order: 2),
        CompactElement(id: "aiIndicator", isVisible: true, fontSize: 0, wing: .right, order: 0),
    ]
}

/// 番茄钟会话记录
struct PomodoroSession: Codable, Identifiable {
    let id: UUID
    let type: PomodoroStatus
    let startTime: Date
    let endTime: Date
    let completed: Bool
    
    init(type: PomodoroStatus, startTime: Date, endTime: Date, completed: Bool) {
        self.id = UUID()
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.completed = completed
    }
}

/// Daily aggregated statistics for calendar view
struct DailyStats: Identifiable {
    let date: Date
    let focusMinutes: Int
    let completedSessions: Int
    let totalSessions: Int
    
    var id: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Complete app backup: config + session history
struct VibeExportData: Codable {
    let config: PomodoroConfig
    let sessions: [PomodoroSession]
    let exportDate: Date
    let appVersion: String
}
