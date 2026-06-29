import SwiftUI
import AppKit

// MARK: - NotchShape

/// 灵动岛外形：顶部完全平直（无视觉缝隙地接续硬件刘海），底部大圆角
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat = 22
    var topCornerRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottomR = max(0, min(bottomCornerRadius, min(rect.width, rect.height) / 2))
        let topR = max(0, min(topCornerRadius, min(rect.width, rect.height) / 2))

        // 起点：左上角（带可选极小圆角，默认 0）
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topR))
        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                radius: topR,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        // 顶边
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))
        if topR > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
                radius: topR,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        // 右侧
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomR))
        // 右下圆角
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomR, y: rect.maxY - bottomR),
            radius: bottomR,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // 底边
        path.addLine(to: CGPoint(x: rect.minX + bottomR, y: rect.maxY))
        // 左下圆角
        path.addArc(
            center: CGPoint(x: rect.minX + bottomR, y: rect.maxY - bottomR),
            radius: bottomR,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - NotchView

/// 刘海主视图：三态联动（空闲 / 紧凑 / 展开）
struct NotchView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var claudeManager: ClaudeSessionManager

    @State private var hoverDebounce: DispatchWorkItem?
    @State private var isHookInstalled: Bool = false
    @State private var isCodexHookInstalled: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // 主体：纯黑刘海形状，与硬件无缝衔接
            NotchShape(bottomCornerRadius: bottomRadius)
                .fill(Color.black)

            content
                .padding(.horizontal, contentHorizontalPadding)
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(NotchShape(bottomCornerRadius: bottomRadius))
        .compositingGroup()
        .contentShape(NotchShape(bottomCornerRadius: bottomRadius))
        .onHover { hovering in
            scheduleHover(hovering)
        }
        .onTapGesture {
            // 设置态/Claude审批态/Claude通知态下不响应主体点击
            guard viewModel.displayState != .settings,
                  viewModel.displayState != .claudeApproval,
                  viewModel.displayState != .claudeNotification else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                viewModel.toggleExpansion()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72),
                   value: viewModel.displayState)
        .animation(.easeInOut(duration: 0.22), value: timer.status)
        .scaleEffect(viewModel.displayState == .expanded ? 1.0 : 0.998)
        .animation(.spring(response: 0.32, dampingFraction: 0.72),
                   value: viewModel.displayState)
    }

    // MARK: - State-driven content

    @ViewBuilder
    private var content: some View {
        switch viewModel.displayState {
        case .idle, .compact:
            compactContent
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        case .expanded:
            expandedContent
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
        case .settings:
            settingsContent
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .breakPrompt:
            breakPromptContent
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        case .claudeApproval:
            claudeApprovalContent
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        case .claudeNotification:
            claudeNotificationContent
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        HStack(spacing: 8) {
            // 极简的"番茄"标识
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 5)

            Text("POMODORO")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(2.4)
                .foregroundColor(Color.white.opacity(0.55))

            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 5)
        }
    }

    // MARK: - Compact

    @State private var claudeDotPulsing: Bool = false
    @State private var claudeSpinAngle: Double = 0

    private var compactContent: some View {
        HStack(spacing: 0) {
            // 左翼：进度环 + 阶段文字 + 倒计时
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: max(0.001, CGFloat(timer.progress)))
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)

                Text(compactStatusLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                Text(timer.formattedTime)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .kerning(0.5)
                    .lineLimit(1)
            }

            // 中央占位空间：物理刘海宽度，不可用于任何内容
            Spacer()
                .frame(width: CGFloat(timer.config.notchGapWidth))

            // 右翼：AI状态（独占右侧空间）
            HStack(spacing: 6) {
                compactAIIndicator
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var compactAIIndicator: some View {
        let sourceLabel = viewModel.activeSource == "codex" ? "Codex" : "AI"
        switch claudeManager.currentPhase {
        case .processing:
            HStack(spacing: 2) {
                Circle()
                    .fill(claudeAmberColor)
                    .frame(width: 6, height: 6)
                    .opacity(claudeDotPulsing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: claudeDotPulsing)
                    .onAppear { claudeDotPulsing = true }
                    .onDisappear { claudeDotPulsing = false }
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(claudeAmberColor)
                if let tool = viewModel.activeToolName {
                    Text("· \(truncatedToolName(tool, maxLength: 8))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(claudeAmberColor)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        case .waitingForInput:
            HStack(spacing: 2) {
                Circle()
                    .fill(claudeGreenColor)
                    .frame(width: 6, height: 6)
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(claudeGreenColor)
                Text("✓")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(claudeGreenColor)
            }
        case .waitingForApproval:
            HStack(spacing: 2) {
                Circle()
                    .fill(claudeRedColor)
                    .frame(width: 6, height: 6)
                    .opacity(claudeDotPulsing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: claudeDotPulsing)
                    .onAppear { claudeDotPulsing = true }
                    .onDisappear { claudeDotPulsing = false }
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(claudeRedColor)
                Text("!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(claudeRedColor)
            }
        case .waitingForResponse:
            HStack(spacing: 2) {
                Circle()
                    .fill(claudeAmberColor)
                    .frame(width: 6, height: 6)
                    .opacity(claudeDotPulsing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: claudeDotPulsing)
                    .onAppear { claudeDotPulsing = true }
                    .onDisappear { claudeDotPulsing = false }
                Text(sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(claudeAmberColor)
                Text("?")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(claudeAmberColor)
            }
        case .compacting:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9))
                .foregroundColor(claudeAmberColor)
                .rotationEffect(.degrees(claudeSpinAngle))
                .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: claudeSpinAngle)
                .onAppear { claudeSpinAngle = 360 }
                .onDisappear { claudeSpinAngle = 0 }
        default:
            EmptyView()
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 8) {
                statusDot
                    .frame(width: 7, height: 7)

                Text(timer.statusText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if timer.status != .idle {
                    Text("\(timer.currentRound)/\(timer.config.roundsBeforeLongBreak)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                        )
                }

                // 设置入口
                Button(action: { viewModel.openSettings() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // 主显示区：左侧大数字时间，右侧细环
            HStack(alignment: .center, spacing: 18) {
                Text(timer.formattedTime)
                    .font(.system(size: 42, weight: .ultraLight, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .kerning(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                progressRing
                    .frame(width: 52, height: 52)
            }
            .padding(.horizontal, 4)

            // 今日统计
            HStack(spacing: 12) {
                Label("\(timer.todayFocusMinutes) 分钟", systemImage: "flame.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))

                Label("\(timer.todayCompletedSessions) 个番茄", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }

            // AI 状态行
            if claudeManager.currentPhase.isActive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(claudeAmberColor)
                        .frame(width: 5, height: 5)
                    Text(viewModel.activeSource == "codex" ? "Codex" : "Claude")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    if let tool = viewModel.activeToolName {
                        Text("· \(truncatedToolName(tool, maxLength: 14))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if viewModel.toolCount > 0 {
                        Text("(\(viewModel.toolCount))")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            // 控制区
            controlBar
        }
    }

    // MARK: - Break Prompt

    private var breakPromptContent: some View {
        VStack(spacing: 12) {
            Text(motivationalMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("休息一下吧")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

            Button(action: {
                viewModel.dismissBreakPrompt()
                timer.startBreak()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 10))
                    Text("开始休息")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(accentColor)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Settings

    private var settingsContent: some View {
        VStack(spacing: 12) {
            // 顶部：返回 + 标题
            HStack {
                Button(action: { viewModel.closeSettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("设置")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // 使标题保持居中的隐形占位
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(.system(size: 11))
                .opacity(0)
            }

            // 可滚动设置内容
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Hook 冲突警告
                    if HookInstaller.isVibeNotchInstalled() {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("检测到 vibe-notch，可能存在 hook 冲突")
                                .font(.system(size: 11))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // 时间
                    settingsSection(title: "时间") {
                        settingsRow(title: "工作", value: timer.config.workDuration / 60, unit: "分钟") {
                            timer.config.workDuration = max(5 * 60, timer.config.workDuration - 5 * 60)
                        } increment: {
                            timer.config.workDuration = min(60 * 60, timer.config.workDuration + 5 * 60)
                        }
                        settingsRow(title: "短休息", value: timer.config.shortBreakDuration / 60, unit: "分钟") {
                            timer.config.shortBreakDuration = max(1 * 60, timer.config.shortBreakDuration - 1 * 60)
                        } increment: {
                            timer.config.shortBreakDuration = min(30 * 60, timer.config.shortBreakDuration + 1 * 60)
                        }
                        settingsRow(title: "长休息", value: timer.config.longBreakDuration / 60, unit: "分钟") {
                            timer.config.longBreakDuration = max(5 * 60, timer.config.longBreakDuration - 5 * 60)
                        } increment: {
                            timer.config.longBreakDuration = min(60 * 60, timer.config.longBreakDuration + 5 * 60)
                        }
                        settingsRow(title: "长休息间隔", value: timer.config.roundsBeforeLongBreak, unit: "轮") {
                            timer.config.roundsBeforeLongBreak = max(2, timer.config.roundsBeforeLongBreak - 1)
                        } increment: {
                            timer.config.roundsBeforeLongBreak = min(8, timer.config.roundsBeforeLongBreak + 1)
                        }
                    }

                    // 行为
                    settingsSection(title: "行为") {
                        settingsToggle(title: "自动开始休息", isOn: $timer.config.autoStartBreak)
                        settingsToggle(title: "自动开始工作", isOn: $timer.config.autoStartWork)
                    }

                    // 显示器
                    settingsSection(title: "显示器") {
                        ForEach(viewModel.connectedDisplays, id: \.self) { displayName in
                            settingsToggle(
                                title: displayName,
                                isOn: Binding<Bool>(
                                    get: {
                                        let selected = timer.config.selectedDisplayNames
                                        if selected.isEmpty {
                                            return displayName.contains("Built-in") || displayName.contains("内建") || displayName.contains("内置")
                                        }
                                        return selected.contains(displayName)
                                    },
                                    set: { newValue in
                                        var selected = timer.config.selectedDisplayNames
                                        if selected.isEmpty {
                                            selected = viewModel.connectedDisplays.filter { name in
                                                name.contains("Built-in") || name.contains("内建") || name.contains("内置")
                                            }
                                        }
                                        if newValue {
                                            if !selected.contains(displayName) {
                                                selected.append(displayName)
                                            }
                                        } else {
                                            if selected.count > 1 {
                                                selected.removeAll { $0 == displayName }
                                            }
                                        }
                                        timer.config.selectedDisplayNames = selected
                                    }
                                )
                            )
                        }
                        settingsRow(title: "刘海宽度", value: timer.config.notchGapWidth, unit: "pt") {
                            timer.config.notchGapWidth = max(200, timer.config.notchGapWidth - 10)
                        } increment: {
                            timer.config.notchGapWidth = min(300, timer.config.notchGapWidth + 10)
                        }
                    }

                    // AI Hooks
                    settingsSection(title: "AI Hooks") {
                        // Claude Code hook status row
                        HStack(spacing: 8) {
                            Image(systemName: isHookInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(isHookInstalled ? Color(red: 0.4, green: 0.86, blue: 0.62) : Color(red: 0.85, green: 0.3, blue: 0.3))
                            Text(isHookInstalled ? "Hook 已安装" : "Hook 未安装")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        // Hook path row
                        HStack {
                            Text("~/.claude/hooks/notch-pomodoro-hook.py")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                        // Action button row
                        HStack {
                            Spacer()
                            Button(action: {
                                HookInstaller.installIfNeeded()
                                isHookInstalled = HookInstaller.isInstalled()
                            }) {
                                Text(isHookInstalled ? "重新安装" : "安装 Hook")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.vertical, 6)

                        // Codex CLI subsection
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                        // Codex status row
                        HStack(spacing: 8) {
                            Image(systemName: isCodexHookInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(isCodexHookInstalled ? Color(red: 0.4, green: 0.86, blue: 0.62) : Color(red: 0.85, green: 0.3, blue: 0.3))
                            Text(isCodexHookInstalled ? "Codex Hook 已安装" : "Codex Hook 未安装")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        // Codex path row
                        HStack {
                            Text("~/.codex/hooks.json")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                        // Codex action button
                        HStack {
                            Spacer()
                            Button(action: {
                                HookInstaller.installCodexIfNeeded()
                                isCodexHookInstalled = HookInstaller.isCodexInstalled()
                            }) {
                                Text(isCodexHookInstalled ? "重新安装" : "安装 Hook")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.vertical, 6)

                        // Trust instruction
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                            Text("首次使用需在 Codex CLI 中运行 /hooks 信任钩子")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        isHookInstalled = HookInstaller.isInstalled()
                        isCodexHookInstalled = HookInstaller.isCodexInstalled()
                    }

                    // 关于
                    HStack {
                        Text("版本")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("1.1.0")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.top, 4)

                    // 退出按钮
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack {
                            Image(systemName: "power")
                                .font(.system(size: 11))
                            Text("退出番茄钟")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 1) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private func settingsRow(
        title: String,
        value: Int,
        unit: String,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 12) {
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                Text("\(value) \(unit)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Claude Approval

    private var claudeApprovalContent: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(claudeAmberColor)
                Text(viewModel.activeSource == "codex" ? "Codex CLI 请求权限" : "Claude Code 请求权限")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(claudeAmberColor)
            }

            // Tool name and input preview
            if case .waitingForApproval(let context) = claudeManager.currentPhase {
                Text("Tool: \(context.toolName)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                if let input = context.formattedInput {
                    Text(input)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }

            Spacer(minLength: 0)

            // Action buttons
            HStack(spacing: 20) {
                Button(action: { claudeManager.approvePermission() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("允许")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.75, blue: 0.45))
                    )
                }
                .buttonStyle(.plain)

                Button(action: { claudeManager.denyPermission() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("拒绝")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.85, green: 0.3, blue: 0.3))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .transition(.opacity)
    }

    // MARK: - Claude Notification

    private var claudeNotificationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            claudeNotificationHeader
            claudeNotificationBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            claudeManager.dismissNotification()
        }
    }

    @ViewBuilder
    private var claudeNotificationHeader: some View {
        let sourceLabel = viewModel.activeSource == "codex" ? "Codex" : "Claude"
        switch claudeManager.currentPhase {
        case .error:
            HStack(spacing: 8) {
                Circle()
                    .fill(claudeRedColor)
                    .frame(width: 8, height: 8)
                Text("\(sourceLabel) 出错")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(claudeRedColor)
            }
        case .waitingForResponse:
            HStack(spacing: 8) {
                Circle()
                    .fill(claudeAmberColor)
                    .frame(width: 8, height: 8)
                Text("\(sourceLabel) 需要你的回复")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(claudeAmberColor)
            }
        default:
            HStack(spacing: 8) {
                Circle()
                    .fill(claudeGreenColor)
                    .frame(width: 8, height: 8)
                Text("\(sourceLabel) 任务完成")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(claudeGreenColor)
            }
        }
    }

    @ViewBuilder
    private var claudeNotificationBody: some View {
        switch claudeManager.currentPhase {
        case .error(let msg):
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
        case .waitingForResponse(let message):
            VStack(alignment: .leading, spacing: 4) {
                if let message = message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
                Text("请切换到终端回复")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("项目: \(claudeManager.projectName ?? "Unknown")")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                Text("等待输入")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Sub-components

    private var statusDot: some View {
        Circle()
            .fill(accentColor)
            .overlay(
                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: 2)
                    .scaleEffect(timer.isPaused ? 1.0 : 1.6)
                    .opacity(timer.isPaused ? 0.0 : 0.0001) // 触发动画但不抢视觉
            )
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 2)

            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(timer.progress)))
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: glyphName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(accentColor)
        }
    }

    @ViewBuilder
    private var controlBar: some View {
        if timer.status == .idle {
            startButton
        } else {
            HStack(spacing: 10) {
                circleButton(
                    icon: timer.isPaused ? "play.fill" : "pause.fill",
                    tint: Color.white.opacity(0.10),
                    foreground: .white
                ) {
                    timer.togglePause()
                }

                circleButton(
                    icon: "forward.end.fill",
                    tint: Color.white.opacity(0.10),
                    foreground: .white
                ) {
                    timer.skip()
                }

                circleButton(
                    icon: "stop.fill",
                    tint: accentColor.opacity(0.18),
                    foreground: accentColor
                ) {
                    timer.stop()
                    timer.resetRounds()
                    viewModel.collapse()
                }
            }
        }
    }

    private var startButton: some View {
        Button(action: {
            if timer.pendingBreak {
                timer.startBreak()
            } else {
                timer.startWork()
            }
            viewModel.collapse()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(timer.pendingBreak ? "开始休息" : "开始专注")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(accentColor)
            )
        }
        .buttonStyle(.plain)
    }

    private func circleButton(
        icon: String,
        tint: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(foreground)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(tint)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hover handling (with debounce)

    private func scheduleHover(_ hovering: Bool) {
        hoverDebounce?.cancel()
        // 进入快速响应（避免迟钝），离开延迟（让用户能在内部移动鼠标）
        let delay: Double = hovering ? 0.05 : 0.30
        let work = DispatchWorkItem { [viewModel] in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                viewModel.isHovering = hovering
            }
        }
        hoverDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Style tokens

    private var bottomRadius: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 18
        case .expanded:       return 24
        case .settings:       return 24
        case .breakPrompt:    return 24
        case .claudeApproval: return 24
        case .claudeNotification: return 22
        }
    }

    private var contentHorizontalPadding: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 12 // 内容已位于左右翼，主体水平内边距收窄
        case .expanded:       return 18
        case .settings:       return 18
        case .breakPrompt:    return 18
        case .claudeApproval: return 18
        case .claudeNotification: return 16
        }
    }

    private var contentTopPadding: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 12
        case .expanded:       return 54
        case .settings:       return 14
        case .breakPrompt:    return 54
        case .claudeApproval: return 54
        case .claudeNotification: return 44
        }
    }

    private var contentBottomPadding: CGFloat {
        switch viewModel.displayState {
        case .idle:        return 12
        case .compact:     return 12
        case .expanded:    return 16
        case .settings:    return 16
        case .breakPrompt: return 16
        case .claudeApproval: return 16
        case .claudeNotification: return 14
        }
    }

    private var glyphName: String {
        switch timer.status {
        case .idle:        return "timer"
        case .working:     return timer.isPaused ? "pause.fill" : "flame.fill"
        case .shortBreak:  return timer.isPaused ? "pause.fill" : "leaf.fill"
        case .longBreak:   return timer.isPaused ? "pause.fill" : "moon.stars.fill"
        case .paused:      return "pause.fill"
        }
    }

    /// 随机激励话语
    private var motivationalMessage: String {
        let messages = [
            "太棒了！又完成了一个番茄钟 🎉",
            "好好休息，让大脑放松一下 ☕",
            "你的专注力真棒！该休息了 💪",
            "做得很好！稍作休息效率更高 ✨",
            "完美！休息是为了走更远的路 🌟",
            "坚持就是胜利！先喝口水吧 💧",
            "专注的你最有魅力！休息一下 🌈"
        ]
        return messages.randomElement() ?? messages[0]
    }

    /// 折叠状态下的简短状态标签
    private var compactStatusLabel: String {
        switch timer.status {
        case .idle:
            return "准备"
        case .working:
            return timer.isPaused ? "暂停" : "专注"
        case .shortBreak:
            return timer.isPaused ? "暂停" : "短休"
        case .longBreak:
            return timer.isPaused ? "暂停" : "长休"
        case .paused:
            return "暂停"
        }
    }

    /// 截断工具名称：超过最大长度时添加省略号
    private func truncatedToolName(_ name: String, maxLength: Int = 8) -> String {
        if name.count > maxLength {
            return String(name.prefix(maxLength - 1)) + "…"
        }
        return name
    }

    /// 状态主色：工作=暖橙，短休=薄荷，长休=冷蓝；闲置=中性灰白
    private var accentColor: Color {
        switch timer.status {
        case .working:
            return Color(red: 0.99, green: 0.55, blue: 0.18) // 番茄/藏红
        case .shortBreak:
            return Color(red: 0.40, green: 0.86, blue: 0.62) // 薄荷
        case .longBreak:
            return Color(red: 0.55, green: 0.70, blue: 1.00) // 冷光蓝
        case .paused:
            return Color(red: 0.80, green: 0.80, blue: 0.85)
        case .idle:
            return Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    // MARK: - Claude Colors

    private var claudeAmberColor: Color {
        Color(red: 0.95, green: 0.7, blue: 0.2)
    }

    private var claudeGreenColor: Color {
        Color(red: 0.4, green: 0.86, blue: 0.62)
    }

    private var claudeRedColor: Color {
        Color(red: 0.85, green: 0.3, blue: 0.3)
    }
}

// MARK: - Preview

struct NotchView_Previews: PreviewProvider {
    static var previews: some View {
        let timer = PomodoroTimer()
        let claude = ClaudeSessionManager()
        let vm = NotchViewModel(timer: timer, claudeManager: claude)

        return Group {
            NotchView(timer: timer, viewModel: vm, claudeManager: claude)
                .frame(width: 350, height: 38)
                .previewDisplayName("Idle")

            NotchView(timer: timer, viewModel: vm, claudeManager: claude)
                .frame(width: 350, height: 36)
                .previewDisplayName("Compact")

            NotchView(timer: timer, viewModel: vm, claudeManager: claude)
                .frame(width: 360, height: 280)
                .previewDisplayName("Expanded")

            NotchView(timer: timer, viewModel: vm, claudeManager: claude)
                .frame(width: 380, height: 420)
                .previewDisplayName("Settings")
        }
        .padding(40)
        .background(Color.gray.opacity(0.25))
    }
}
