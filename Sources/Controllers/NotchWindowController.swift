import AppKit
import SwiftUI
import Combine

// MARK: - Display State

/// 灵动岛显示阶段：闲置 / 紧凑 / 展开 / 设置 / 日历 / Claude审批 / Claude问题 / Claude通知
enum NotchDisplayState: Equatable {
    case idle      // 计时器空闲，最小指示器
    case compact   // 计时进行中，紧凑信息
    case expanded  // 悬停或点击展开，完整控制面板
    case settings  // 设置面板
    case calendar  // 日历面板
    case breakPrompt  // 休息提示弹窗（半高）
    case claudeApproval    // Claude Code 权限请求 UI
    case claudeQuestion    // Claude Code 问题选择 UI
    case claudeNotification // Claude Code 任务完成/错误通知
}

// MARK: - View Model

/// 刘海视图共享状态：被 SwiftUI 视图与 NSWindowController 同时观察
final class NotchViewModel: ObservableObject {
    /// 已连接的显示器名称列表（由 NotchDisplayManager 设置，供设置界面使用）
    @Published var connectedDisplays: [String] = []
    /// 用户主动点击展开（持久状态，需用户再次点击或鼠标离开后撤销）
    @Published var isPinnedExpanded: Bool = false
    /// 鼠标悬停（带延迟去抖）
    @Published var isHovering: Bool = false
    /// 是否打开设置面板（最高优先级，强制进入 .settings 态）
    @Published var showSettings: Bool = false
    /// 是否打开日历面板
    @Published var showCalendar: Bool = false
    /// 计时器是否处于活跃状态
    @Published private(set) var isTimerActive: Bool = false
    /// 冷启动就绪标志：用于在窗口初始定位完成前忽略悬停展开
    @Published private(set) var isReady: Bool = false
    /// 派生状态，驱动窗口尺寸与视图布局
    @Published private(set) var displayState: NotchDisplayState = .idle
    /// 是否显示休息提示（工作完成后自动触发，5秒后消失）
    @Published var showBreakPrompt: Bool = false
    /// Claude 会话阶段
    @Published var claudePhase: ClaudeSessionPhase = .idle
    /// 当前活跃 AI 源 ("claude" 或 "codex")
    @Published var activeSource: String = "claude"
    /// 当前活跃源的累计工具调用次数
    @Published var toolCount: Int = 0
    /// 当前活跃源最近使用的工具名
    @Published var activeToolName: String? = nil
    /// 活跃会话计数
    @Published var activeSessionCount: Int = 0
    /// 当前审批请求后排队等待的审批数
    @Published var pendingApprovalCount: Int = 0
    /// Hook 安装状态
    @Published var isHookInstalled: Bool = false
    @Published var isCodexHookInstalled: Bool = false
    private var breakPromptDismissWork: DispatchWorkItem?

    let claudeManager: ClaudeSessionManager
    private var cancellables = Set<AnyCancellable>()

    init(timer: PomodoroTimer, claudeManager: ClaudeSessionManager) {
        self.claudeManager = claudeManager

        // 监听 timer 状态以更新 isTimerActive
        timer.$status
            .map { $0 != .idle }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$isTimerActive)

        // 工作完成时触发休息提示
        timer.$didCompleteWork
            .filter { $0 == true }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.triggerBreakPrompt()
            }
            .store(in: &cancellables)

        // Batch-sync all Claude manager properties in a single pass
        claudeManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.claudePhase = self.claudeManager.currentPhase
                self.activeSource = self.claudeManager.activeSource
                self.toolCount = self.claudeManager.toolCount
                self.activeToolName = self.claudeManager.lastToolName
            }
            .store(in: &cancellables)

        // 订阅活跃会话数变化
        claudeManager.$activeSessionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.activeSessionCount = count }
            .store(in: &cancellables)

        // 订阅待处理审批数量变化
        claudeManager.$pendingApprovalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.pendingApprovalCount = count }
            .store(in: &cancellables)

        // 多态合并：设置 > 日历 > Claude审批 > Claude问题 > 休息提示 > Claude通知 > 展开 > 紧凑 > 闲置
        Publishers.CombineLatest4(
            Publishers.CombineLatest4($isPinnedExpanded, $isHovering, $isTimerActive, $showSettings),
            Publishers.CombineLatest($isReady, $showCalendar),
            $showBreakPrompt,
            $claudePhase
        )
            .map { quad, readyCalendar, breakPrompt, claude -> NotchDisplayState in
                let (pinned, hovering, active, settings) = quad
                let (ready, calendar) = readyCalendar
                if settings { return .settings }
                if calendar { return .calendar }
                if claude.isWaitingForApproval { return .claudeApproval }
                if claude.isAskingQuestion { return .claudeQuestion }
                if breakPrompt { return .breakPrompt }
                if claude.isNotification { return .claudeNotification }
                if pinned || (hovering && ready) { return .expanded }
                if active { return .compact }
                return .idle
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$displayState)

        // 延迟开启 hover 响应，避免冷启动时鼠标恰好处于刘海区域而立即展开
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isHovering = false  // 清除冷启动期间积累的悬停状态
            self?.isReady = true
        }
    }

    /// 切换点击展开
    func toggleExpansion() {
        isPinnedExpanded.toggle()
    }

    /// 打开设置面板
    func openSettings() {
        showCalendar = false
        showSettings = true
    }

    /// 关闭设置面板
    func closeSettings() {
        showSettings = false
    }

    /// 打开日历面板
    func openCalendar() {
        showSettings = false
        showCalendar = true
    }

    /// 关闭日历面板
    func closeCalendar() {
        showCalendar = false
    }

    /// 收起所有展开状态（用于按钮触发后回到刘海形态）
    func collapse() {
        isPinnedExpanded = false
        isHovering = false
        showSettings = false
        showCalendar = false
        breakPromptDismissWork?.cancel()
        breakPromptDismissWork = nil
    }

    /// 触发休息提示（5秒后自动消失）
    func triggerBreakPrompt() {
        showBreakPrompt = true
        breakPromptDismissWork?.cancel()
        breakPromptDismissWork = nil
        let work = DispatchWorkItem { [weak self] in
            self?.showBreakPrompt = false
        }
        breakPromptDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    /// 手动关闭休息提示
    func dismissBreakPrompt() {
        breakPromptDismissWork?.cancel()
        showBreakPrompt = false
    }
}

// MARK: - Window Controller

/// 刘海区域窗口控制器：负责窗口构造、置顶定位与跟随 ViewModel 动态调整尺寸
final class NotchWindowController: NSWindowController {
    private let timer: PomodoroTimer
    private let claudeManager: ClaudeSessionManager
    let viewModel: NotchViewModel
    private var assignedScreen: NSScreen  // 分配的显示器（非 let，因为重连时对象可能变化）
    private var cancellables = Set<AnyCancellable>()

    init(timer: PomodoroTimer, claudeManager: ClaudeSessionManager, screen: NSScreen) {
        self.timer = timer
        self.claudeManager = claudeManager
        self.viewModel = NotchViewModel(timer: timer, claudeManager: claudeManager)
        self.assignedScreen = screen

        let initialSize = NSSize(width: CGFloat(timer.config.compactWidth), height: 38)
        let window = NotchWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 完全透明的承载窗口；视觉外观由 SwiftUI 中的自定义 Shape 提供
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // 高于菜单栏，与系统刘海视觉无缝衔接
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true

        super.init(window: window)

        setupHostingController()
        bindViewModel()
        repositionWindow(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupHostingController() {
        guard let window = window else { return }

        let root = NotchRootView(timer: timer, viewModel: viewModel, claudeManager: claudeManager)
        let hosting = NSHostingController(rootView: root)
        // 让 hosting view 自适应容器，由窗口尺寸驱动 SwiftUI 布局
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.autoresizingMask = [.width, .height]
        window.contentViewController = hosting
    }

    private func bindViewModel() {
        viewModel.$displayState
            .removeDuplicates()
            .dropFirst() // 初始化时已通过 repositionWindow 设置过
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionWindow(animated: true)
            }
            .store(in: &cancellables)

        // Reposition when config changes (user adjusts width in settings)
        timer.$config
            .removeDuplicates(by: { $0.compactWidth == $1.compactWidth && $0.expandedWidth == $1.expandedWidth })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionWindow(animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    @objc private func screenParametersChanged() {
        // 确认分配的屏幕仍然连接（frame 非零表示活跃）
        if NSScreen.screens.contains(where: { $0.localizedName == assignedScreen.localizedName }) {
            repositionWindow(animated: false)
        }
    }

    /// 根据配置计算窗口尺寸
    private func windowSize(for state: NotchDisplayState) -> NSSize {
        let config = timer.config
        switch state {
        case .idle, .compact:
            return NSSize(width: CGFloat(config.compactWidth), height: 38)
        case .expanded:
            return NSSize(width: CGFloat(config.expandedWidth), height: 280)
        case .settings:
            return NSSize(width: CGFloat(config.expandedWidth) + 20, height: 420)
        case .calendar:
            return NSSize(width: CGFloat(config.expandedWidth) + 20, height: 350)
        case .breakPrompt:
            return NSSize(width: CGFloat(config.expandedWidth), height: 180)
        case .claudeApproval:
            return NSSize(width: CGFloat(config.compactWidth), height: 260)
        case .claudeQuestion:
            return NSSize(width: CGFloat(config.compactWidth), height: 300)
        case .claudeNotification:
            return NSSize(width: CGFloat(config.expandedWidth), height: 140)
        }
    }

    /// 计算并应用窗口 frame：顶边贴合屏幕顶端，向下生长
    private func repositionWindow(animated: Bool) {
        guard let window = window else { return }
        let screen = assignedScreen

        let size = windowSize(for: viewModel.displayState)
        let screenFrame = screen.frame
        let originX = screenFrame.midX - size.width / 2
        // NSWindow 坐标原点在左下；让顶边对齐 screenFrame.maxY
        let originY = screenFrame.maxY - size.height
        let newFrame = NSRect(x: originX, y: originY, width: size.width, height: size.height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22, 0.88, 0.32, 1.0 // 更接近自然弹性的强 ease-out
                )
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    /// 更新分配的显示器（用于显示器重连时同名屏幕对象可能变化）
    func updateScreen(_ screen: NSScreen) {
        assignedScreen = screen
        repositionWindow(animated: false)
    }

    // MARK: - Visibility

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NotchWindow

/// 自定义 NSPanel：允许成为 key window 以响应内部按钮点击，但不抢占主窗口语义
final class NotchWindow: NSPanel {
    /// 关键修复：允许成为 key window，否则面板内的 SwiftUI 按钮无法接收点击
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 点击时主动成为 key window，确保 nonactivatingPanel 下按钮可响应
    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}

// MARK: - SwiftUI Root

/// SwiftUI 根容器：承担 ViewModel 注入与全宽填充
struct NotchRootView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var claudeManager: ClaudeSessionManager

    var body: some View {
        NotchView(timer: timer, viewModel: viewModel, claudeManager: claudeManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}
