import SwiftUI

/// Colours taken from the app icon: its deep blue arrow (#0050DC), light blue
/// arrow (#78B5F5), and warm off-white tile. Green is kept only for success.
enum UpkeepPalette {
    /// The icon's deep blue.
    static let blue = Color(red: 0.00, green: 0.31, blue: 0.86)
    /// The icon's light blue.
    static let sky = Color(red: 0.47, green: 0.71, blue: 0.96)
    /// A deep navy that carries the blues on dark surfaces.
    static let navy = Color(red: 0.035, green: 0.09, blue: 0.22)

    static func accent(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.49, green: 0.72, blue: 0.97)
            : Color(red: 0.04, green: 0.31, blue: 0.82)
    }

    static func canvas(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.09, blue: 0.125)
            : Color(red: 0.957, green: 0.953, blue: 0.941)
    }

    static func surface(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.13, blue: 0.175)
            : Color(red: 0.995, green: 0.993, blue: 0.988)
    }
}

struct WorkspaceGlyph: View {
    @Environment(\.colorScheme) private var scheme
    let systemImage: String
    var size: CGFloat = 42
    var color: Color?

    var body: some View {
        let foreground = color ?? UpkeepPalette.accent(in: scheme)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(foreground.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

struct WorkspaceSectionLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.15)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct WorkspaceAppearance: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(UpkeepPalette.canvas(in: scheme))
            .accentColor(UpkeepPalette.accent(in: scheme))
            .tint(UpkeepPalette.accent(in: scheme))
    }
}

private struct WorkspaceSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background(UpkeepPalette.surface(in: scheme), in: shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.10)).allowsHitTesting(false) }
    }
}

extension View {
    func upkeepWorkspaceAppearance() -> some View {
        modifier(WorkspaceAppearance())
    }

    func upkeepSurface(radius: CGFloat = 12) -> some View {
        modifier(WorkspaceSurface(radius: radius))
    }
}

struct WorkspaceEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: Text?
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            WorkspaceGlyph(systemImage: systemImage, size: 48)
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let description {
                description
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension WorkspaceEmptyState where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init(title: title, systemImage: systemImage, description: description, actions: { EmptyView() })
    }
}

/// Shown instead of an empty state while a check that could fill the list runs.
struct WorkspaceScanningState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct WorkspaceDialogFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                content
            }
            .padding(.horizontal, UpkeepLayout.pageInset)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WorkspaceSectionLabel(title: title)
            content.upkeepOutlinedInspectorCard()
        }
    }
}
