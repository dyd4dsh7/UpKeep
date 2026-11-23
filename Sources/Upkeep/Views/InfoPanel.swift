import SwiftUI

/// The single inspector layout for applications, packages, and models.
struct InfoPanel<Header: View, Content: View>: View {
    @UpkeepStoreReference private var store
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                header
                Button {
                    store.clearInspectorSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close details")
                .accessibilityLabel("Close details")
                // No Escape shortcut: it would steal Escape from search and text fields.
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, UpkeepLayout.pageInset)
                .padding(.vertical, 20)
                .background(UpkeepPalette.surface(in: scheme))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: UpkeepLayout.sectionSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(UpkeepLayout.pageInset)
                .disclosureGroupStyle(InspectorDisclosureStyle())
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

struct InfoPanelHeader<Icon: View, Detail: View>: View {
    let title: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold)).lineLimit(2)
                    .tracking(-0.35)
                    .accessibilityAddTraits(.isHeader)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: 8) {
                    detail
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The installed version and the version an update brings, for an inspector header.
struct InspectorVersionChange: View {
    let current: String
    let latest: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { versions }
            VStack(alignment: .leading, spacing: 2) { versions }
        }
        .font(.body.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Version \(current), update to \(latest)")
    }

    @ViewBuilder
    private var versions: some View {
        Text(current)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(latest)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .layoutPriority(1)
    }
}

/// The inspector's action card: status, one prominent primary action, and
/// quieter secondary actions in a footer.
struct InspectorActionCard<Status: View, Primary: View, Secondary: View, Options: View>: View {
    let systemImage: String
    let color: Color
    let optionsLabel: String
    let optionsHelp: String?
    @ViewBuilder let status: Status
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary
    @ViewBuilder let options: Options

    init(
        systemImage: String,
        color: Color = .accentColor,
        optionsLabel: String = "Update options",
        optionsHelp: String? = nil,
        @ViewBuilder status: () -> Status,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder options: () -> Options
    ) {
        self.systemImage = systemImage
        self.color = color
        self.optionsLabel = optionsLabel
        self.optionsHelp = optionsHelp
        self.status = status()
        self.primary = primary()
        self.secondary = secondary()
        self.options = options()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) { status }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    optionsMenu
                }
                .controlSize(.regular)
                primary
            }
            .padding(UpkeepLayout.cardPadding)
            .controlSize(.large)
            .modifier(FlexibleButtonSizing())
            if Secondary.self != EmptyView.self {
                Divider()
                InspectorActionTiles { secondary }
                    .padding(Self.footerInset)
            }
        }
        .upkeepSurface(radius: UpkeepLayout.actionCardRadius)
    }

    static var footerInset: CGFloat { 6 }

    private var optionsMenu: some View {
        Menu { options } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(optionsHelp ?? optionsLabel)
        .accessibilityLabel(optionsLabel)
    }
}

extension InspectorActionCard where Secondary == EmptyView {
    init(
        systemImage: String,
        color: Color = .accentColor,
        optionsLabel: String = "Update options",
        optionsHelp: String? = nil,
        @ViewBuilder status: () -> Status,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder options: () -> Options
    ) {
        self.init(systemImage: systemImage, color: color, optionsLabel: optionsLabel, optionsHelp: optionsHelp,
                  status: status, primary: primary, secondary: { EmptyView() }, options: options)
    }
}

/// Lets the primary action fill the card where macOS supports flexible buttons.
private struct FlexibleButtonSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonSizing(.flexible)
        } else {
            content
        }
    }
}

/// Secondary actions as equal-width tiles with the icon above the title. Pass
/// buttons whose labels are `Label`s. Tiles wrap into a grid when narrow.
struct InspectorActionTiles<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { content }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                content
            }
        }
        .buttonStyle(InspectorTileButtonStyle())
        .labelStyle(InspectorTileLabelStyle())
        .controlSize(.regular)
    }
}

struct InspectorTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InspectorTile(configuration: configuration)
    }
}

private struct InspectorTile: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let configuration: ButtonStyleConfiguration

    /// Concentric with the action card's corners around the footer inset.
    private var radius: CGFloat {
        UpkeepLayout.actionCardRadius - InspectorActionCard<EmptyView, EmptyView, EmptyView, EmptyView>.footerInset
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            // The ideal width lets four tiles share a row at the inspector's minimum width.
            .frame(minWidth: 0, idealWidth: 56, maxWidth: .infinity, minHeight: 52)
            .background(shape.fill(.primary.opacity(fillOpacity)))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
            .upkeepAnimated(for: isHovered, animation: UpkeepMotion.quick)
    }

    private var fillOpacity: Double {
        if configuration.isPressed { return 0.12 }
        return isHovered && isEnabled ? 0.06 : 0
    }
}

struct InspectorTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(height: 20)
            configuration.title
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Inspector disclosure sections as full-width rows on a card, with the
/// chevron trailing and the whole row clickable.
struct InspectorDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        InspectorDisclosure(configuration: configuration)
    }
}

private struct InspectorDisclosure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    let configuration: DisclosureGroupStyleConfiguration

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UpkeepLayout.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : UpkeepMotion.standard) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, UpkeepLayout.cardPadding)
                .frame(minHeight: 40)
                .background(Color.primary.opacity(isHovered ? 0.04 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .upkeepAnimated(for: isHovered, animation: UpkeepMotion.quick)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides this section")

            if configuration.isExpanded {
                Divider()
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(UpkeepLayout.cardPadding)
                    .upkeepStateTransition()
            }
        }
        .clipShape(shape)
        .upkeepSurface(radius: UpkeepLayout.cardRadius)
    }
}
