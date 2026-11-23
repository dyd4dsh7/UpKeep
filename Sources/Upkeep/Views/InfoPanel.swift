import SwiftUI

/// The single inspector layout for applications, packages, and models.
struct InfoPanel<Header: View, Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
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

/// The top of every details panel: who the item is, then what state it is in.
///
///     [icon]  Name
///             What it is, in one or two lines
///     [1.0 → 1.1] [Running] [GitHub]
///     Last checked 2 min ago
struct InfoPanelHeader<Icon: View, Facts: View>: View {
    static var iconSize: CGFloat { 56 }

    let title: String
    var subtitle: String?
    var status: ItemCheckStatus?
    @ViewBuilder let icon: Icon
    @ViewBuilder let facts: Facts

    init(
        title: String,
        subtitle: String? = nil,
        status: ItemCheckStatus? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder facts: () -> Facts
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.icon = icon()
        self.facts = facts()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                icon.frame(width: Self.iconSize, height: Self.iconSize)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .tracking(-0.35)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                        .textSelection(.enabled)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .help(subtitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InspectorCloseButton()
            }
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 6) { facts }
                status
            }
        }
    }
}

/// Closes the details panel. It sits level with the item's icon and name,
/// and fills in on hover like other toolbar-style buttons.
struct InspectorCloseButton: View {
    @UpkeepStoreReference private var store
    @State private var isHovering = false

    var body: some View {
        Button {
            store.clearInspectorSelection()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(isHovering ? 0.14 : 0.07), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Close details")
        .accessibilityLabel("Close details")
        // No Escape shortcut: it would steal Escape from search and text fields.
    }
}

/// A small capsule label for a fact about the selected item. Neutral unless
/// given a tint.
struct InfoChip: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        .background((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.13), in: Capsule())
    }
}

/// The installed version, and the version an update brings, as a header chip.
struct InspectorVersionChip: View {
    let current: String
    var latest: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(current)
                .foregroundStyle(latest == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            if let latest {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(latest)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(latest == nil ? Color.primary.opacity(0.07) : Color.accentColor.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(latest.map { "Version \(current), update to \($0)" } ?? "Version \(current)")
    }
}

/// Lays views out left to right, wrapping onto new lines. A view wider than
/// the line is narrowed to fit, so long versions truncate instead of spilling.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Row { var items: [(index: Int, x: CGFloat, size: CGSize)] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: size.height))
                size.width = min(size.width, width)
            }
            let x = row.items.isEmpty ? 0 : row.width + spacing
            if !row.items.isEmpty, x + size.width > width {
                let nextY = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: nextY)
                row.items.append((index, 0, size))
                row.width = size.width
                row.height = size.height
                continue
            }
            row.items.append((index, x, size))
            row.width = x + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
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
