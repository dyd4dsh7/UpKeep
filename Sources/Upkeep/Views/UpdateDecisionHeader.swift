import SwiftUI

struct UpdateDecisionHeader: View {
    @UpkeepStoreReference private var store

    let review: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                briefing
                    .frame(maxWidth: .infinity, alignment: .leading)
                UpdateArtwork(symbol: symbol)
                    .frame(width: 218)
                    .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)

            briefing.frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            LinearGradient(
                colors: [UpkeepPalette.forest, Color(red: 0.10, green: 0.31, blue: 0.23)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(UpkeepPalette.mint.opacity(0.22))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .upkeepAnimated(for: store.totalUpdateCount)
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Update Centre", systemImage: "arrow.down.circle")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(UpkeepPalette.mint)

            Text(title)
                .font(.system(size: 36, weight: .semibold))
                .tracking(-1.35)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(.callout)
                .foregroundStyle(UpkeepPalette.mint.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            primaryAction
                .buttonStyle(UpdateReviewButtonStyle())
                .padding(.top, 7)
        }
        .padding(24)
    }

    @ViewBuilder private var primaryAction: some View {
        if batchCount > 0 {
            Button(action: review) {
                Label("Review Updates…", systemImage: "arrow.right")
                    .labelStyle(UpdateReviewLabelStyle())
            }
            .disabled(store.isWorking(.unifiedBatch))
        } else if systemCount > 0, store.settings.checkMacOS {
            Button {
                store.selection = .macOSUpdates
            } label: {
                Label("Review macOS Updates", systemImage: "arrow.right")
                    .labelStyle(UpdateReviewLabelStyle())
            }
        } else if store.updateCheckState == .disabled {
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
                    .labelStyle(UpdateReviewLabelStyle())
            }
        } else {
            Button {
                Task { await store.scan() }
            } label: {
                Label(store.isScanning ? "Checking…" : "Check for Updates", systemImage: "arrow.clockwise")
                    .labelStyle(UpdateReviewLabelStyle())
            }
            .disabled(store.isScanning)
        }
    }

    private var batchCount: Int { store.availableBatchUpdateItems.count }
    private var recommendedCount: Int { store.recommendedBatchUpdateItems.count }
    private var systemCount: Int { store.macOSUpdates.count { !$0.isFullInstaller } }

    private var title: String {
        let total = store.totalUpdateCount
        if total > 0 { return "\(WorkspaceSummary.count(total, "update", "updates")) available" }
        return store.updateCheckState == .complete ? "You’re up to date" : store.updateCheckState.title
    }

    private var detail: String {
        if batchCount > 0 {
            let attention = batchCount - recommendedCount
            var parts: [String] = []
            if recommendedCount > 0 { parts.append("\(recommendedCount.formatted()) recommended") }
            if attention > 0 { parts.append("\(attention.formatted()) to review") }
            if systemCount > 0 { parts.append("\(systemCount.formatted()) via Software Update") }
            return parts.joined(separator: " · ")
        }
        if systemCount > 0 {
            return "Install macOS updates through Software Update."
        }
        if store.totalUpdateCount > 0 {
            return "Choose an update below to see its installation options."
        }
        return store.updateCheckState.detail
    }

    private var symbol: String {
        if store.totalUpdateCount > 0 { return "arrow.down" }
        switch store.updateCheckState {
        case .complete: return "checkmark"
        case .failed, .partial: return "exclamationmark"
        case .disabled: return "pause"
        case .notChecked, .checking: return "arrow.clockwise"
        }
    }
}

private struct UpdateReviewLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.title
            configuration.icon.accessibilityHidden(true)
        }
    }
}

private struct UpdateReviewButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(UpkeepPalette.forest)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(UpkeepPalette.mint.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.55)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .inset(by: -3)
                    .strokeBorder(focused ? UpkeepPalette.mint : .clear, lineWidth: 2)
            }
            .fixedSize()
    }
}

private struct UpdateArtwork: View {
    let symbol: String

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width * 0.62, y: size.height * 0.5)
                let ink = UpkeepPalette.mint

                for radius: CGFloat in [62, 88, 116, 145] {
                    let orbit = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: orbit), with: .color(ink.opacity(0.23)), lineWidth: 1)
                }

                var guides = Path()
                guides.move(to: CGPoint(x: 12, y: center.y))
                guides.addLine(to: CGPoint(x: size.width, y: center.y))
                guides.move(to: CGPoint(x: center.x, y: 10))
                guides.addLine(to: CGPoint(x: center.x, y: size.height - 10))
                context.stroke(guides, with: .color(ink.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

                for (radius, angle) in [(62.0, 2.6), (88.0, -2.15), (116.0, 1.95), (145.0, -0.8)] {
                    let x = center.x + cos(angle) * radius
                    let y = center.y + sin(angle) * radius
                    context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(ink.opacity(0.85)))
                }
            }
            .frame(width: 218)
            .frame(minHeight: 172)

            Image(systemName: symbol)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(UpkeepPalette.mint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 77, height: 77)
                .background(UpkeepPalette.forest, in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(UpkeepPalette.mint.opacity(0.6))
                }
                .offset(x: 26)
        }
        .accessibilityHidden(true)
    }
}
