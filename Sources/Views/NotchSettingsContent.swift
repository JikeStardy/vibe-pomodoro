import SwiftUI
import AppKit

// MARK: - NotchView Settings Content

extension NotchView {

    var settingsContent: some View {
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

                        settingsRow(title: "收起宽度", value: timer.config.compactWidth, unit: "pt") {
                            timer.config.compactWidth = max(350, timer.config.compactWidth - 10)
                        } increment: {
                            timer.config.compactWidth = min(500, timer.config.compactWidth + 10)
                        }

                        settingsRow(title: "展开宽度", value: timer.config.expandedWidth, unit: "pt") {
                            timer.config.expandedWidth = max(300, timer.config.expandedWidth - 10)
                        } increment: {
                            timer.config.expandedWidth = min(480, timer.config.expandedWidth + 10)
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
                            Text("~/.claude/hooks/vibe-pomodoro-hook.py")
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
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
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
}
