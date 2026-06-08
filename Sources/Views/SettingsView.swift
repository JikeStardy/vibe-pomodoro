import SwiftUI

/// 设置视图
struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("设置")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // 时间设置
                    SettingsSection(title: "时间设置", icon: "clock") {
                        DurationRow(title: "工作时长", 
                                   value: $timer.config.workDuration,
                                   range: 5...60,
                                   step: 5,
                                   unit: "分钟")
                        
                        DurationRow(title: "短休息", 
                                   value: $timer.config.shortBreakDuration,
                                   range: 1...30,
                                   step: 1,
                                   unit: "分钟")
                        
                        DurationRow(title: "长休息", 
                                   value: $timer.config.longBreakDuration,
                                   range: 5...60,
                                   step: 5,
                                   unit: "分钟")
                        
                        StepperRow(title: "长休息间隔",
                                  value: $timer.config.roundsBeforeLongBreak,
                                  range: 2...8,
                                  unit: "轮")
                    }
                    
                    // 行为设置
                    SettingsSection(title: "行为设置", icon: "gearshape") {
                        ToggleRow(title: "自动开始休息",
                                 subtitle: "工作结束后自动进入休息",
                                 isOn: $timer.config.autoStartBreak)
                        
                        ToggleRow(title: "自动开始工作",
                                 subtitle: "休息结束后自动开始工作",
                                 isOn: $timer.config.autoStartWork)
                    }
                    
                    // 显示设置
                    SettingsSection(title: "显示设置", icon: "display") {
                        ToggleRow(title: "刘海区域显示",
                                 subtitle: "在屏幕刘海区域显示计时器",
                                 isOn: $timer.config.showInNotch)
                        
                        ToggleRow(title: "菜单栏显示",
                                 subtitle: "在菜单栏显示计时器状态",
                                 isOn: $timer.config.showInMenuBar)
                    }
                    
                    // 关于
                    SettingsSection(title: "关于", icon: "info.circle") {
                        HStack {
                            Text("版本")
                            Spacer()
                            Text("1.1.0")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("恢复默认") {
                    resetToDefault()
                }
                .buttonStyle(.borderless)
                
                Button("退出应用") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 360, height: 500)
    }
    
    private func resetToDefault() {
        timer.config = PomodoroConfig.default
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            VStack(spacing: 12) {
                content()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
            )
        }
    }
}

// MARK: - Duration Row
struct DurationRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: { 
                    value = max(range.lowerBound, value - step * 60)
                }) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                
                Text("\(value / 60) \(unit)")
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 50)
                
                Button(action: { 
                    value = min(range.upperBound * 60, value + step * 60)
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Stepper Row
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            
            Spacer()
            
            Stepper(value: $value, in: range) {
                Text("\(value) \(unit)")
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
            }
            .labelsHidden()
            
            Text("\(value) \(unit)")
                .font(.system(size: 13, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: - Toggle Row
struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    
    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(timer: PomodoroTimer())
    }
}
