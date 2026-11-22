import SwiftUI

enum UpkeepPalette {
    static let mint = Color(red: 0.73, green: 0.96, blue: 0.75)
    static let forest = Color(red: 0.06, green: 0.19, blue: 0.15)

    static func accent(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.56, green: 0.88, blue: 0.69)
            : Color(red: 0.10, green: 0.39, blue: 0.28)
    }

    static func canvas(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.11, blue: 0.105)
            : Color(red: 0.949, green: 0.961, blue: 0.948)
    }

    static func surface(in scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.127, green: 0.153, blue: 0.14)
            : Color(red: 0.993, green: 0.996, blue: 0.989)
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
