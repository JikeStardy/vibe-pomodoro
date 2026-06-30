import SwiftUI

// MARK: - NotchView Claude Approval

extension NotchView {

    var claudeApprovalContent: some View {
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
}
