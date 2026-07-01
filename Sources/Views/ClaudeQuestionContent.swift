import SwiftUI

// MARK: - NotchView Claude Question

extension NotchView {

    var claudeQuestionContent: some View {
        VStack(spacing: 10) {
            if case .askingQuestion(let context) = claudeManager.currentPhase,
               let firstQ = context.questions.first {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(claudeAmberColor)
                    Text(firstQ.header ?? "选择")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }

                // Question text
                Text(firstQ.question)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Options (if any)
                if let options = firstQ.options, !options.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                                Button(action: {
                                    claudeManager.answerQuestion(answers: [firstQ.question: option.label])
                                }) {
                                    HStack {
                                        Text(option.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                        Spacer()
                                        if let desc = option.description {
                                            Text(desc)
                                                .font(.system(size: 10))
                                                .foregroundColor(.white.opacity(0.5))
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }

                Spacer(minLength: 0)

                // Free input + submit (always available as "Other")
                HStack(spacing: 8) {
                    TextField("输入回复...", text: questionInputBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                        )

                    Button(action: {
                        if case .askingQuestion(let ctx) = claudeManager.currentPhase,
                           let q = ctx.questions.first {
                            claudeManager.answerQuestion(answers: [q.question: questionInput])
                            questionInput = ""
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(claudeAmberColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(questionInput.isEmpty)
                }
            }
        }
        .transition(.opacity)
    }

    var questionInputBinding: Binding<String> {
        Binding(
            get: { self.questionInput },
            set: { self.questionInput = $0 }
        )
    }
}
