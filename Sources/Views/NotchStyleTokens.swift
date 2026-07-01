import SwiftUI

// MARK: - NotchView Style Tokens

extension NotchView {

    var bottomRadius: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 18
        case .expanded:       return 24
        case .settings:       return 24
        case .calendar:       return 24
        case .breakPrompt:    return 24
        case .claudeApproval: return 24
        case .claudeQuestion: return 24
        case .claudeNotification: return 22
        }
    }

    var contentHorizontalPadding: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 12 // 内容已位于左右翼，主体水平内边距收窄
        case .expanded:       return 18
        case .settings:       return 18
        case .calendar:       return 18
        case .breakPrompt:    return 18
        case .claudeApproval: return 18
        case .claudeQuestion: return 18
        case .claudeNotification: return 16
        }
    }

    var contentTopPadding: CGFloat {
        switch viewModel.displayState {
        case .idle, .compact: return 12
        case .expanded:       return 54
        case .settings:       return 14
        case .calendar:       return 14
        case .breakPrompt:    return 54
        case .claudeApproval: return 54
        case .claudeQuestion: return 54
        case .claudeNotification: return 44
        }
    }

    var contentBottomPadding: CGFloat {
        switch viewModel.displayState {
        case .idle:        return 12
        case .compact:     return 12
        case .expanded:    return 16
        case .settings:    return 16
        case .calendar:    return 16
        case .breakPrompt: return 16
        case .claudeApproval: return 16
        case .claudeQuestion: return 16
        case .claudeNotification: return 14
        }
    }

    var glyphName: String {
        switch timer.status {
        case .idle:        return "timer"
        case .working:     return timer.isPaused ? "pause.fill" : "flame.fill"
        case .shortBreak:  return timer.isPaused ? "pause.fill" : "leaf.fill"
        case .longBreak:   return timer.isPaused ? "pause.fill" : "moon.stars.fill"
        case .paused:      return "pause.fill"
        }
    }

    /// 随机激励话语
    var motivationalMessage: String {
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
    var compactStatusLabel: String {
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

    /// 状态主色：工作=暖橙，短休=薄荷，长休=冷蓝；闲置=中性灰白
    var accentColor: Color {
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

    var claudeAmberColor: Color {
        Color(red: 0.95, green: 0.7, blue: 0.2)
    }

    var claudeGreenColor: Color {
        Color(red: 0.4, green: 0.86, blue: 0.62)
    }

    var claudeRedColor: Color {
        Color(red: 0.85, green: 0.3, blue: 0.3)
    }
}
