import Foundation

/// Local JSON file storage for pomodoro sessions.
/// Path: ~/Library/Application Support/VibePomodoro/sessions.json
class SessionStorage {
    static let shared = SessionStorage()
    
    private let fileManager = FileManager.default
    private var cachedSessions: [PomodoroSession]?
    
    /// Application Support directory for this app
    private var appSupportDir: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VibePomodoro", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Path to sessions.json
    var filePath: URL {
        appSupportDir.appendingPathComponent("sessions.json")
    }
    
    /// Load all sessions from JSON file
    func loadSessions() -> [PomodoroSession] {
        if let cached = cachedSessions { return cached }
        guard fileManager.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let sessions = try? JSONDecoder().decode([PomodoroSession].self, from: data) else {
            return []
        }
        cachedSessions = sessions
        return sessions
    }
    
    /// Save all sessions to JSON file
    func saveSessions(_ sessions: [PomodoroSession]) {
        cachedSessions = sessions
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: filePath, options: .atomic)
    }
    
    /// Append a single session
    func appendSession(_ session: PomodoroSession) {
        var sessions = loadSessions()
        sessions.append(session)
        saveSessions(sessions)
    }
    
    /// Import sessions from external file, deduplicate by (startTime, type, duration)
    /// Returns count of newly added sessions
    func importFromFile(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([PomodoroSession].self, from: data) else {
            return 0
        }
        var existing = loadSessions()
        let existingSet = Set(existing.map { "\($0.startTime.timeIntervalSince1970)-\($0.type.rawValue)" })
        let newSessions = imported.filter { !existingSet.contains("\($0.startTime.timeIntervalSince1970)-\($0.type.rawValue)") }
        existing.append(contentsOf: newSessions)
        existing.sort { $0.startTime < $1.startTime }
        saveSessions(existing)
        return newSessions.count
    }
    
    /// Get file size in bytes
    var fileSize: Int64 {
        guard let attrs = try? fileManager.attributesOfItem(atPath: filePath.path) else { return 0 }
        return attrs[.size] as? Int64 ?? 0
    }
    
    /// Migrate from UserDefaults (one-time on first launch)
    func migrateFromUserDefaults() {
        // Only migrate if JSON file doesn't exist yet
        guard !fileManager.fileExists(atPath: filePath.path) else { return }
        guard let data = UserDefaults.standard.data(forKey: "pomodoro_sessions"),
              let sessions = try? JSONDecoder().decode([PomodoroSession].self, from: data) else {
            return
        }
        saveSessions(sessions)
        print("[VibePomodoro] Migrated \(sessions.count) sessions from UserDefaults to JSON file")
    }
    
    /// Invalidate cache (e.g., after external import)
    func invalidateCache() {
        cachedSessions = nil
    }
}
