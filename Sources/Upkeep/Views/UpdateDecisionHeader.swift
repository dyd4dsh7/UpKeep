import SwiftUI

struct UpdateDecisionHeader: View {
    let recommendedCount: Int
    let attentionCount: Int
    let isWorking: Bool
    let review: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                heading.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 24)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                heading
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .upkeepAnimated(for: recommendedCount)
        .upkeepAnimated(for: attentionCount)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .contentTransition(.numericText())
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(buttonTitle, action: review)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
                .disabled(isWorking || recommendedCount + attentionCount == 0)
        }
    }

    private var title: String {
        if recommendedCount > 0 {
            return recommendedCount == 1 ? "1 recommended update" : "\(recommendedCount) recommended updates"
        }
        return "Updates need review"
    }

    private var detail: String {
        if recommendedCount > 0 {
            return attentionCount > 0
                ? "All sources · \(attentionCount) more to review"
                : "Ready to review and install"
        }
        return "Review installation options before updating."
    }

    private var buttonTitle: String {
        "Review Updates…"
    }
}
