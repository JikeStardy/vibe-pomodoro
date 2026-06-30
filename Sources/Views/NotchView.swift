import SwiftUI
import AppKit

// MARK: - NotchView

/// 刘海主视图：三态联动（空闲 / 紧凑 / 展开）
struct NotchView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var claudeManager: ClaudeSessionManager

    @State private var hoverDebounce: DispatchWorkItem?
    @State var isHookInstalled: Bool = false
    @State var isCodexHookInstalled: Bool = false
    @State private var claudeDotPulsing: Bool = false
    @State private var claudeSpinAngle: Double = 0

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

    // MARK: - Compact

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

    // MARK: - Hover handling (with debounce)

    private func scheduleHover(_ hovering: Bool) {
        hoverDebounce?.cancel()
        // 进入快速响应（避免迟钝），离开延迟（让用户能在内部移动鼠标）
        let delay: Double = hovering ? 0.05 : 0.30
        let work = DispatchWorkItem { [viewModel] in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                viewModel.isHovering = hovering
                // 鼠标离开时重置 pin 状态，确保面板一定能收起
                if !hovering {
                    viewModel.isPinnedExpanded = false
                }
            }
        }
        hoverDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
