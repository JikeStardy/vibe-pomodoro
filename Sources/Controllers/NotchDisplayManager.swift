import AppKit
import Combine

/// 多显示器 Notch 窗口管理器：为每个选中的显示器创建独立的 NotchWindowController
final class NotchDisplayManager {
    private let timer: PomodoroTimer
    private let claudeManager: ClaudeSessionManager
    private var controllers: [String: NotchWindowController] = [:] // key = screen.localizedName
    private var cancellables = Set<AnyCancellable>()

    init(timer: PomodoroTimer, claudeManager: ClaudeSessionManager) {
        self.timer = timer
        self.claudeManager = claudeManager

        // 监听屏幕连接/断开
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 监听配置变化（显示器选择）
        timer.$config
            .map(\.selectedDisplayNames)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshWindows()
            }
            .store(in: &cancellables)

        // 初始刷新
        refreshWindows()
    }

    @objc private func screenParametersChanged() {
        refreshWindows()
    }

    /// 同步窗口实例与当前配置 + 已连接屏幕
    func refreshWindows() {
        let connectedScreens = NSScreen.screens
        let connectedNames = connectedScreens.map(\.localizedName)
        let selectedNames = resolvedSelectedNames()

        // 关闭不再需要的窗口（屏幕断开或被取消选中）
        let toRemove = controllers.keys.filter { name in
            !connectedNames.contains(name) || !selectedNames.contains(name)
        }
        for name in toRemove {
            controllers[name]?.hide()
            controllers[name] = nil
        }

        // 为新选中的屏幕创建窗口或更新现有窗口的屏幕引用
        for screen in connectedScreens {
            let name = screen.localizedName
            guard selectedNames.contains(name) else { continue }

            if let existing = controllers[name] {
                // 屏幕对象可能在重连后变化，更新引用
                existing.updateScreen(screen)
            } else {
                let controller = NotchWindowController(timer: timer, claudeManager: claudeManager, screen: screen)
                controller.show()
                controllers[name] = controller
            }
        }

        // 更新所有 ViewModel 的 connectedDisplays（供设置界面使用）
        updateConnectedDisplays(connectedNames)
    }

    /// 解析实际要展示的显示器名称
    private func resolvedSelectedNames() -> [String] {
        let selected = timer.config.selectedDisplayNames
        if selected.isEmpty {
            // 默认：仅内建显示器
            if let builtIn = NSScreen.screens.first(where: { isBuiltInDisplay($0) }) {
                return [builtIn.localizedName]
            }
            // 找不到内建则回退到主屏幕
            return [NSScreen.main?.localizedName].compactMap { $0 }
        }
        return selected
    }

    /// 判断是否为内建显示器
    private func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName
        return name.contains("Built-in") || name.contains("内建") || name.contains("内置")
    }

    /// 更新所有窗口 ViewModel 上的 connectedDisplays 列表
    private func updateConnectedDisplays(_ names: [String]) {
        for (_, controller) in controllers {
            controller.viewModel.connectedDisplays = names
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
