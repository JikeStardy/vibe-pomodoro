import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                                        guard viewModel.connectedDisplays.contains(displayName) else { return }
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
                            Image(systemName: viewModel.isHookInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(viewModel.isHookInstalled ? Color(red: 0.4, green: 0.86, blue: 0.62) : Color(red: 0.85, green: 0.3, blue: 0.3))
                            Text(viewModel.isHookInstalled ? "Hook 已安装" : "Hook 未安装")
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
                                viewModel.isHookInstalled = HookInstaller.isInstalled()
                            }) {
                                Text(viewModel.isHookInstalled ? "重新安装" : "安装 Hook")
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
                            Image(systemName: viewModel.isCodexHookInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(viewModel.isCodexHookInstalled ? Color(red: 0.4, green: 0.86, blue: 0.62) : Color(red: 0.85, green: 0.3, blue: 0.3))
                            Text(viewModel.isCodexHookInstalled ? "Codex Hook 已安装" : "Codex Hook 未安装")
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
                                viewModel.isCodexHookInstalled = HookInstaller.isCodexInstalled()
                            }) {
                                Text(viewModel.isCodexHookInstalled ? "重新安装" : "安装 Hook")
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
                        viewModel.isHookInstalled = HookInstaller.isInstalled()
                        viewModel.isCodexHookInstalled = HookInstaller.isCodexInstalled()
                    }

                    // 布局
                    settingsSection(title: "布局") {
                        ForEach(Array(timer.config.compactLayout.elements.enumerated()), id: \.element.id) { index, element in
                            HStack(spacing: 8) {
                                // Visibility toggle
                                Toggle("", isOn: Binding(
                                    get: { timer.config.compactLayout.elements[index].isVisible },
                                    set: { timer.config.compactLayout.elements[index].isVisible = $0 }
                                ))
                                .toggleStyle(.switch)
                                .scaleEffect(0.6)
                                .frame(width: 36)

                                // Element name
                                Text(element.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 60, alignment: .leading)

                                // Wing selector
                                Picker("", selection: Binding(
                                    get: { timer.config.compactLayout.elements[index].wing },
                                    set: { timer.config.compactLayout.elements[index].wing = $0 }
                                )) {
                                    Text("左").tag(CompactElement.Wing.left)
                                    Text("右").tag(CompactElement.Wing.right)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 60)

                                // Font size stepper (0 = default)
                                HStack(spacing: 2) {
                                    Button(action: {
                                        let current = timer.config.compactLayout.elements[index].fontSize
                                        timer.config.compactLayout.elements[index].fontSize = max(0, current - 1)
                                    }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)

                                    Text(element.fontSize == 0 ? "默认" : "\(element.fontSize)pt")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 32)

                                    Button(action: {
                                        let current = timer.config.compactLayout.elements[index].fontSize
                                        let newVal = current == 0 ? 10 : current + 1
                                        timer.config.compactLayout.elements[index].fontSize = min(20, newVal)
                                    }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Spacer()

                                // Order buttons (within same wing)
                                VStack(spacing: 0) {
                                    Button(action: { moveElement(at: index, direction: -1) }) {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { moveElement(at: index, direction: 1) }) {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }

                        // Reset button
                        Button(action: {
                            timer.config.compactLayout = .default
                        }) {
                            Text("恢复默认布局")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    }

                    // 数据
                    settingsSection(title: "数据") {
                        // Session count
                        HStack {
                            Text("会话记录")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(SessionStorage.shared.loadSessions().count) 条")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        // Export button
                        Button(action: { exportData() }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11))
                                Text("导出备份")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)

                        // Import button
                        Button(action: { importData() }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 11))
                                Text("导入备份")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
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

    // MARK: - Export / Import

    private func moveElement(at index: Int, direction: Int) {
        var elements = timer.config.compactLayout.elements
        let element = elements[index]
        // Find elements in same wing
        let sameWing = elements.enumerated().filter { $0.element.wing == element.wing }.sorted { $0.element.order < $1.element.order }
        guard let wingIndex = sameWing.firstIndex(where: { $0.offset == index }) else { return }
        let targetWingIndex = wingIndex + direction
        guard targetWingIndex >= 0 && targetWingIndex < sameWing.count else { return }

        // Swap orders
        let targetGlobalIndex = sameWing[targetWingIndex].offset
        let tempOrder = elements[index].order
        elements[index].order = elements[targetGlobalIndex].order
        elements[targetGlobalIndex].order = tempOrder
        timer.config.compactLayout.elements = elements
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vibe-pomodoro-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            let exportData = VibeExportData(
                config: timer.config,
                sessions: SessionStorage.shared.loadSessions(),
                exportDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(exportData) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard let data = try? Data(contentsOf: url) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Try new format first (VibeExportData)
            if let backup = try? decoder.decode(VibeExportData.self, from: data) {
                // Restore config
                timer.config = backup.config
                // Merge sessions
                let existing = SessionStorage.shared.loadSessions()
                let existingSet = Set(existing.map { "\($0.startTime.timeIntervalSince1970)-\($0.type.rawValue)" })
                let newSessions = backup.sessions.filter { !existingSet.contains("\($0.startTime.timeIntervalSince1970)-\($0.type.rawValue)") }
                if !newSessions.isEmpty {
                    var all = existing
                    all.append(contentsOf: newSessions)
                    all.sort { $0.startTime < $1.startTime }
                    SessionStorage.shared.saveSessions(all)
                }
                timer.refreshTodayStats()
            } else if (try? JSONDecoder().decode([PomodoroSession].self, from: data)) != nil {
                // Fallback: old format (just sessions array)
                let count = SessionStorage.shared.importFromFile(url)
                if count > 0 {
                    timer.refreshTodayStats()
                }
            }
        }
    }
}
