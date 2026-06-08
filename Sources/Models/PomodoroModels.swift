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
    var showInNotch: Bool = true          // 在刘海区域显示
    var showInMenuBar: Bool = true        // 在菜单栏显示
    
    static let `default` = PomodoroConfig()
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
