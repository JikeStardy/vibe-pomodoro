import Foundation
import Combine

/// 审批请求 FIFO 队列管理器
/// 当多个 AI agent 同时运行时，权限审批请求可能快速连续到达。
/// 此管理器维护一个全局 FIFO 队列，确保所有审批都被处理，不会丢失。
class EventQueueManager: ObservableObject {
    @Published private(set) var pendingCount: Int = 0

    struct QueuedApproval {
        let source: String          // "claude" / "codex"
        let context: PermissionContext
        let projectName: String?
        let enqueuedAt: Date
        var isStale: Bool { Date().timeIntervalSince(enqueuedAt) > 360 }
    }

    private var queue: [QueuedApproval] = []
    private let maxQueueSize = 20
    private let lock = NSLock()

    init() {
        startStaleSweep()
    }

    /// Enqueue a new approval request at the end of the queue
    func enqueue(source: String, context: PermissionContext, projectName: String?) {
        lock.lock()
        // If queue is full, remove the oldest item (its socket will timeout anyway)
        if queue.count >= maxQueueSize {
            queue.removeFirst()
        }
        queue.append(QueuedApproval(
            source: source,
            context: context,
            projectName: projectName,
            enqueuedAt: Date()
        ))
        let count = queue.count
        lock.unlock()

        DispatchQueue.main.async {
            self.pendingCount = count
        }
    }

    /// Pop the next approval from the front of the queue (FIFO)
    func popNext() -> QueuedApproval? {
        lock.lock()
        guard !queue.isEmpty else {
            lock.unlock()
            DispatchQueue.main.async { self.pendingCount = 0 }
            return nil
        }
        let item = queue.removeFirst()
        let count = queue.count
        lock.unlock()

        // Skip stale items
        if item.isStale {
            return popNext()  // Recursively try next
        }

        DispatchQueue.main.async {
            self.pendingCount = count
        }
        return item
    }

    /// Remove stale items (older than 360 seconds)
    func removeStaleItems() {
        lock.lock()
        queue.removeAll { $0.isStale }
        let count = queue.count
        lock.unlock()

        DispatchQueue.main.async {
            self.pendingCount = count
        }
    }

    /// Remove a specific item by toolUseId (e.g., when socket times out)
    func removeItem(toolUseId: String) {
        lock.lock()
        queue.removeAll { $0.context.toolUseId == toolUseId }
        let count = queue.count
        lock.unlock()

        DispatchQueue.main.async {
            self.pendingCount = count
        }
    }

    /// Periodic sweep every 60 seconds to remove stale items
    private func startStaleSweep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.removeStaleItems()
            self?.startStaleSweep()
        }
    }
}
