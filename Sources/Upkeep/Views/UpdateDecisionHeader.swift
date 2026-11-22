import SwiftUI

struct UpdateDecisionHeader: View {
    @UpkeepStoreReference private var store
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var eyebrowSize: CGFloat = 11

    let review: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                briefing
                    .frame(maxWidth: .infinity, alignment: .leading)
                UpdateArtwork(symbol: symbol, palette: palette)
                    .frame(width: 200)
                    .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)

            briefing.frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(palette.outline)
                .allowsHitTesting(false)
        }
        .environment(\.updateHeroPalette, palette)
        .accessibilityElement(children: .contain)
        .upkeepAnimated(for: store.totalUpdateCount)
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Update Centre", systemImage: "arrow.down.circle")
                .font(.system(size: eyebrowSize, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(palette.eyebrow)

            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-1.1)
                .foregroundStyle(palette.title)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(.callout)
                .foregroundStyle(palette.detail)
                .fixedSize(horizontal: false, vertical: true)

            primaryAction
                .buttonStyle(UpdateReviewButtonStyle())
                .padding(.top, 5)
        }
        .padding(20)
    }

    private var palette: UpdateHeroPalette { UpdateHeroPalette(scheme: scheme) }

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
        return store.updateCheckState == .complete
            ? "You’re up to date"
            : store.updateCheckState.title(lastChecked: store.lastChecked)
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
        return store.updateCheckState.detail(lastChecked: store.lastChecked)
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

/// Hero colours from the app icon: a navy card with light blue in dark mode,
/// and a pale blue card with the icon's deep blue in light mode.
struct UpdateHeroPalette {
    let background: [Color]
    let outline: Color
    let eyebrow: Color
    let title: Color
    let detail: Color
    let ink: Color
    let tile: Color
    let buttonFill: Color
    let buttonText: Color

    init(scheme: ColorScheme) {
        if scheme == .dark {
            background = [UpkeepPalette.navy, Color(red: 0.05, green: 0.17, blue: 0.40)]
            outline = UpkeepPalette.sky.opacity(0.25)
            eyebrow = UpkeepPalette.sky
            title = .white
            detail = UpkeepPalette.sky.opacity(0.86)
            ink = UpkeepPalette.sky
            tile = UpkeepPalette.navy
            buttonFill = UpkeepPalette.sky
            buttonText = UpkeepPalette.navy
        } else {
            background = [Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.80, green: 0.88, blue: 0.99)]
            outline = UpkeepPalette.navy.opacity(0.12)
            eyebrow = UpkeepPalette.blue
            title = UpkeepPalette.navy
            detail = UpkeepPalette.navy.opacity(0.72)
            ink = UpkeepPalette.blue
            tile = Color(red: 0.98, green: 0.99, blue: 1.0)
            buttonFill = UpkeepPalette.blue
            buttonText = .white
        }
    }
}

private struct UpdateHeroPaletteKey: EnvironmentKey {
    static let defaultValue = UpdateHeroPalette(scheme: .dark)
}

extension EnvironmentValues {
    var updateHeroPalette: UpdateHeroPalette {
        get { self[UpdateHeroPaletteKey.self] }
        set { self[UpdateHeroPaletteKey.self] = newValue }
    }
}

private struct UpdateReviewButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.updateHeroPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(palette.buttonText)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(palette.buttonFill.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.55)
            .overlay {
                // Insetting by -3 grows the radius to 11: concentric with the 8pt fill.
                RoundedRectangle(cornerRadius: 8)
                    .inset(by: -3)
                    .strokeBorder(focused ? palette.buttonFill : .clear, lineWidth: 2)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .fixedSize()
    }
}

private struct UpdateArtwork: View {
    let symbol: String
    let palette: UpdateHeroPalette

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width * 0.62, y: size.height * 0.5)
                let ink = palette.ink

                for radius: CGFloat in [52, 74, 98, 124] {
                    let orbit = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: orbit), with: .color(ink.opacity(0.23)), lineWidth: 1)
                }

                var guides = Path()
                guides.move(to: CGPoint(x: 12, y: center.y))
                guides.addLine(to: CGPoint(x: size.width, y: center.y))
                guides.move(to: CGPoint(x: center.x, y: 10))
                guides.addLine(to: CGPoint(x: center.x, y: size.height - 10))
                context.stroke(guides, with: .color(ink.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

                for (radius, angle) in [(52.0, 2.6), (74.0, -2.15), (98.0, 1.95), (124.0, -0.8)] {
                    let x = center.x + cos(angle) * radius
                    let y = center.y + sin(angle) * radius
                    context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(ink.opacity(0.85)))
                }
            }
            .frame(width: 200)
            .frame(minHeight: 140)

            Image(systemName: symbol)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 64, height: 64)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17).strokeBorder(palette.ink.opacity(0.5))
                }
                .offset(x: 24)
        }
        .accessibilityHidden(true)
    }
}
