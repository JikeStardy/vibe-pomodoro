import SwiftUI

// MARK: - NotchView Sub-components

extension NotchView {

    var statusDot: some View {
        Circle()
            .fill(accentColor)
            .overlay(
                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: 2)
                    .scaleEffect(timer.isPaused ? 1.0 : 1.6)
                    .opacity(timer.isPaused ? 0.0 : 0.0001) // 触发动画但不抢视觉
            )
    }

    var progressRing: some View {
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
    var controlBar: some View {
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

    // MARK: - Tool Name Helpers

    /// 截断工具名称：超过最大长度时添加省略号
    func truncatedToolName(_ name: String, maxLength: Int = 8) -> String {
        if name.count > maxLength {
            return String(name.prefix(maxLength - 1)) + "…"
        }
        return name
    }
}
