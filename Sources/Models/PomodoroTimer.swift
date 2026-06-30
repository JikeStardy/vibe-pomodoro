import Foundation
import Combine
import UserNotifications

/// 番茄钟定时器管理器
class PomodoroTimer: ObservableObject {
    // MARK: - Published Properties
    @Published var status: PomodoroStatus = .idle
    @Published var timeRemaining: Int
    @Published var currentRound: Int = 1
    @Published var isPaused: Bool = false
    @Published var pendingBreak: Bool = false  // 下一步应为休息
    @Published var didCompleteWork: Bool = false
    
    @Published var todayFocusMinutes: Int = 0
    @Published var todayBreakMinutes: Int = 0
    @Published var todayCompletedSessions: Int = 0
    
    // MARK: - Configuration
    @Published var config: PomodoroConfig {
        didSet {
            saveConfig()
        }
    }
    
    // MARK: - Private Properties
    private var timer: Timer?
    private var startDate: Date?
    private var pausedTimeRemaining: Int?
    private var sessionStartTime: Date?
    private var sessionTotalTime: Int = 0
    
    // MARK: - Callbacks
    var onStatusChange: ((PomodoroStatus) -> Void)?
    var onTick: ((Int) -> Void)?
    var onComplete: ((PomodoroStatus) -> Void)?
    
    // MARK: - Computed Properties
    var totalTime: Int {
        switch status {
        case .working:
            return config.workDuration
        case .shortBreak:
            return config.shortBreakDuration
        case .longBreak:
            return config.longBreakDuration
        default:
            return config.workDuration
        }
    }
    
    var progress: Double {
        let activeTotal = status != .idle ? sessionTotalTime : totalTime
        guard activeTotal > 0 else { return 0 }
        return 1.0 - (Double(timeRemaining) / Double(activeTotal))
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var statusText: String {
        switch status {
        case .idle:
            return "准备开始"
        case .working:
            return isPaused ? "工作暂停" : "专注工作"
        case .shortBreak:
            return isPaused ? "休息暂停" : "短休息"
        case .longBreak:
            return isPaused ? "休息暂停" : "长休息"
        case .paused:
            return "已暂停"
        }
    }
    
    // MARK: - Initialization
    init() {
        self.config = PomodoroConfig.default
        self.timeRemaining = PomodoroConfig.default.workDuration
        let loaded = loadConfig()
        config = loaded
        timeRemaining = loaded.workDuration
        refreshTodayStats()
    }
    
    // MARK: - Public Methods
    
    /// 开始工作
    func startWork() {
        didCompleteWork = false
        pendingBreak = false
        stop()
        status = .working
        timeRemaining = config.workDuration
        sessionTotalTime = config.workDuration
        isPaused = false
        sessionStartTime = Date()
        startTimer()
        onStatusChange?(status)
    }
    
    /// 开始休息
    func startBreak() {
        didCompleteWork = false
        pendingBreak = false
        stop()
        let isLongBreak = currentRound > config.roundsBeforeLongBreak
        status = isLongBreak ? .longBreak : .shortBreak
        timeRemaining = isLongBreak ? config.longBreakDuration : config.shortBreakDuration
        sessionTotalTime = isLongBreak ? config.longBreakDuration : config.shortBreakDuration
        isPaused = false
        sessionStartTime = Date()
        startTimer()
        onStatusChange?(status)
    }
    
    /// 暂停/继续
    func togglePause() {
        guard status == .working || status == .shortBreak || status == .longBreak else { return }
        
        if isPaused {
            resume()
        } else {
            pause()
        }
    }
    
    /// 停止
    func stop() {
        guard status != .idle else { return }
        pendingBreak = false
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        startDate = nil
        pausedTimeRemaining = nil
        
        if let startTime = sessionStartTime {
            let session = PomodoroSession(
                type: status,
                startTime: startTime,
                endTime: Date(),
                completed: timeRemaining == 0
            )
            saveSession(session)
            refreshTodayStats()
            sessionStartTime = nil
        }
        
        status = .idle
        isPaused = false
        timeRemaining = config.workDuration
        onStatusChange?(status)
    }
    
    /// 跳过当前阶段
    func skip() {
        guard status != .idle else { return }
        
        let completedStatus = status
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        
        // 保存当前会话
        if let startTime = sessionStartTime {
            let session = PomodoroSession(
                type: completedStatus,
                startTime: startTime,
                endTime: Date(),
                completed: true
            )
            saveSession(session)
            refreshTodayStats()
            sessionStartTime = nil
        }
        
        // 切换到下一阶段
        if completedStatus == .working {
            currentRound += 1
            if config.autoStartBreak {
                startBreak()
            } else {
                pendingBreak = true
                status = .idle
                timeRemaining = config.shortBreakDuration
                onStatusChange?(status)
            }
        } else {
            if completedStatus == .longBreak {
                currentRound = 1
            }
            if config.autoStartWork {
                startWork()
            } else {
                status = .idle
                timeRemaining = config.workDuration
                onStatusChange?(status)
            }
        }
        
        onComplete?(completedStatus)
    }
    
    /// 重置轮次
    func resetRounds() {
        currentRound = 1
    }
    
    /// 刷新今日统计数据
    func refreshTodayStats() {
        let sessions = loadSessions()
        let calendar = Calendar.current
        let todaySessions = sessions.filter { calendar.isDateInToday($0.startTime) }
        
        todayFocusMinutes = Int(round(todaySessions
            .filter { $0.type == .working }
            .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) } / 60.0))
        
        todayBreakMinutes = Int(round(todaySessions
            .filter { $0.type == .shortBreak || $0.type == .longBreak }
            .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) } / 60.0))
        
        todayCompletedSessions = todaySessions
            .filter { $0.type == .working && $0.completed }
            .count
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func pause() {
        guard !isPaused, status != .idle else { return }
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        isPaused = true
        pausedTimeRemaining = timeRemaining
        onStatusChange?(status)
    }
    
    private func resume() {
        guard isPaused, status != .idle else { return }
        // 防止重复创建定时器
        timer?.invalidate()
        timer = nil
        isPaused = false
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        onStatusChange?(status)
    }
    
    private func tick() {
        guard let startDate = startDate else { return }
        
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let initialTime = pausedTimeRemaining ?? sessionTotalTime
        
        timeRemaining = max(0, initialTime - elapsed)
        onTick?(timeRemaining)
        
        if timeRemaining == 0 {
            complete()
        }
    }
    
    private func complete() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        pausedTimeRemaining = nil
        
        let completedStatus = status
        
        // 保存会话
        if let startTime = sessionStartTime {
            let session = PomodoroSession(
                type: completedStatus,
                startTime: startTime,
                endTime: Date(),
                completed: true
            )
            saveSession(session)
            refreshTodayStats()
            sessionStartTime = nil
        }
        
        // 发送通知
        sendNotification(for: completedStatus)
        
        // 自动切换或等待
        if completedStatus == .working {
            currentRound += 1
            didCompleteWork = true
            if config.autoStartBreak {
                startBreak()
            } else {
                pendingBreak = true
                status = .idle
                timeRemaining = currentRound > config.roundsBeforeLongBreak 
                    ? config.longBreakDuration 
                    : config.shortBreakDuration
                isPaused = false
                onStatusChange?(status)
            }
        } else {
            if completedStatus == .longBreak {
                currentRound = 1
            }
            if config.autoStartWork {
                startWork()
            } else {
                status = .idle
                timeRemaining = config.workDuration
                isPaused = false
                onStatusChange?(status)
            }
        }
        
        onComplete?(completedStatus)
    }
    
    private func sendNotification(for status: PomodoroStatus) {
        let content = UNMutableNotificationContent()
        
        switch status {
        case .working:
            content.title = "工作完成！"
            content.body = "休息一下吧 🎉"
            content.sound = .default
        case .shortBreak, .longBreak:
            content.title = "休息结束"
            content.body = "准备开始新的番茄钟 💪"
            content.sound = .default
        default:
            break
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Persistence
    
    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "pomodoro_config")
        }
    }
    
    private func loadConfig() -> PomodoroConfig {
        guard let data = UserDefaults.standard.data(forKey: "pomodoro_config") else {
            return PomodoroConfig.default
        }
        if let config = try? JSONDecoder().decode(PomodoroConfig.self, from: data) {
            return config
        }
        // Fallback: try partial decode
        print("[NotchPomodoro] Config decode failed, attempting migration fallback")
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return PomodoroConfig(
                workDuration: dict["workDuration"] as? Int ?? 1500,
                shortBreakDuration: dict["shortBreakDuration"] as? Int ?? 300,
                longBreakDuration: dict["longBreakDuration"] as? Int ?? 900,
                roundsBeforeLongBreak: dict["roundsBeforeLongBreak"] as? Int ?? 4,
                autoStartBreak: dict["autoStartBreak"] as? Bool ?? false,
                autoStartWork: dict["autoStartWork"] as? Bool ?? false,
                selectedDisplayNames: dict["selectedDisplayNames"] as? [String] ?? [],
                notchGapWidth: dict["notchGapWidth"] as? Int ?? 240
            )
        }
        return PomodoroConfig.default
    }
    
    private func saveSession(_ session: PomodoroSession) {
        var sessions = loadSessions()
        sessions.append(session)
        // 只保留最近100条记录
        if sessions.count > 100 {
            sessions = Array(sessions.suffix(100))
        }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: "pomodoro_sessions")
        }
    }
    
    private func loadSessions() -> [PomodoroSession] {
        guard let data = UserDefaults.standard.data(forKey: "pomodoro_sessions"),
              let sessions = try? JSONDecoder().decode([PomodoroSession].self, from: data) else {
            return []
        }
        return sessions
    }
}
