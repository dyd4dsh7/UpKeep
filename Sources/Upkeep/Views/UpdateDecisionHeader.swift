import SwiftUI

struct UpdateDecisionHeader: View {
    let recommendedCount: Int
    let attentionCount: Int
    let isWorking: Bool
    let review: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.bold())
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            UpdateDecisionMetric(
                value: recommendedCount,
                label: "Recommended",
                systemImage: "checkmark.shield.fill",
                color: .green
            )
            UpdateDecisionMetric(
                value: attentionCount,
                label: "Review",
                systemImage: "hand.raised.fill",
                color: .orange
            )

            Button(buttonTitle, action: review)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .upkeepAnimated(for: recommendedCount)
        .upkeepAnimated(for: attentionCount)
    }

    private var title: String {
        if recommendedCount > 0 {
            return recommendedCount == 1 ? "1 Update Is Ready" : "\(recommendedCount) Updates Are Ready"
        }
        return "Updates Need Your Attention"
    }

    private var detail: String {
        if recommendedCount > 0 {
            return "Stable updates Upkeep can complete directly are selected by default."
        }
        return "These updates open another app, change a major version, or affect developer tools."
    }

    private var buttonTitle: String {
        recommendedCount > 0 ? "Review Recommended" : "Review Updates"
    }
}

private struct UpdateDecisionMetric: View {
    let value: Int
    let label: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased()) updates")
    }
}
