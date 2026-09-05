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
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .upkeepAnimated(for: recommendedCount)
        .upkeepAnimated(for: attentionCount)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(buttonTitle, action: review)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
                .disabled(isWorking)
        }
    }

    private var title: String {
        if recommendedCount > 0 {
            return recommendedCount == 1 ? "1 update ready" : "\(recommendedCount) updates ready"
        }
        return "Review available updates"
    }

    private var detail: String {
        if recommendedCount > 0 {
            return attentionCount > 0
                ? "Across all sources: \(attentionCount) additional items need review."
                : "Review the selected updates before installing."
        }
        return "These updates open another app, change a major version, or affect developer tools."
    }

    private var buttonTitle: String {
        recommendedCount > 0 ? "Review Recommended" : "Review Updates"
    }
}
