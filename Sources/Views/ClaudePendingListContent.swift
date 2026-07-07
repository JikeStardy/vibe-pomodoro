import SwiftUI

// MARK: - NotchView Claude Pending List

extension NotchView {

    var claudePendingListContent: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Text("待处理请求 (\(viewModel.queueItems.count))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: { viewModel.closePendingList() }) {
                    Text("返回")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }

            // Queue list or empty state
            if viewModel.queueItems.isEmpty {
                Spacer()
                Text("暂无待处理请求")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(viewModel.queueItems, id: \.context.toolUseId) { item in
                            pendingListRow(item: item)
                        }
                    }
                }
            }
        }
        .padding(16)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    // MARK: - Row

    private func pendingListRow(item: EventQueueManager.QueuedApproval) -> some View {
        Button(action: {
            claudeManager.eventQueue.promoteItem(toolUseId: item.context.toolUseId)
            viewModel.closePendingList()
        }) {
            HStack(spacing: 10) {
                // Source tag
                Text(item.source == "codex" ? "Codex" : "Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(item.source == "codex"
                                  ? Color(red: 0.3, green: 0.75, blue: 0.45)
                                  : Color(red: 0.3, green: 0.5, blue: 0.9))
                    )

                // Tool name
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.context.toolName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let project = item.projectName {
                        Text(project)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Relative time
                Text(relativeTime(from: item.enqueuedAt))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s前" }
        let minutes = seconds / 60
        return "\(minutes)m前"
    }
}
