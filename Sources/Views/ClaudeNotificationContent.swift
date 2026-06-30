import SwiftUI

// MARK: - NotchView Claude Notification

extension NotchView {

    var claudeNotificationContent: some View {
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
}
