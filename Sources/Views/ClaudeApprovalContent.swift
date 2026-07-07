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
                if viewModel.pendingApprovalCount > 0 {
                    Button(action: { viewModel.openPendingList() }) {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10))
                            Text("+\(viewModel.pendingApprovalCount)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(claudeAmberColor.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(claudeAmberColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
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
            HStack(spacing: 12) {
                Button(action: { claudeManager.approvePermission() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("允许")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.75, blue: 0.45))
                    )
                }
                .buttonStyle(.plain)

                // "Always Allow" button — only shown when suggestions are available
                if case .waitingForApproval(let context) = claudeManager.currentPhase,
                   let suggestions = context.suggestions, !suggestions.isEmpty {
                    Button(action: { claudeManager.approvePermissionAlways() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("始终允许")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.2, green: 0.55, blue: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { claudeManager.denyPermission() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("拒绝")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
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
