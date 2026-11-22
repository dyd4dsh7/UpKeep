import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var state = SetupViewState()
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 29

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                setupOptions
            }
            .frame(idealHeight: 307, maxHeight: 340)

            footer
        }
        .frame(width: 640)
        .upkeepWorkspaceAppearance()
    }

    private var setupOptions: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Update sources", detail: "Choose what to manage.")

                ForEach(SetupProfile.allCases) { profile in
                    profileButton(profile)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Navigation", detail: "Choose which tools to see.")

                ForEach(SidebarViewMode.allCases) { mode in
                    viewModeButton(mode)
                }
            }
            .frame(width: 205)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        WorkspaceDialogFooter {
            Label("No account required", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") {
                settings.completeSetup(state.profile, sidebarViewMode: state.sidebarViewMode)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            AppBrandIcon(size: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("Set up Upkeep")
                    .font(.system(size: titleSize, weight: .semibold))
                    .tracking(-0.9)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose what to include in update checks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func profileButton(_ profile: SetupProfile) -> some View {
        let isSelected = state.profile == profile
        return Button { state.profile = profile } label: {
            HStack(spacing: 14) {
                Image(systemName: profile.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(profile.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.14),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func viewModeButton(_ mode: SidebarViewMode) -> some View {
        let isSelected = state.sidebarViewMode == mode
        return Button { state.sidebarViewMode = mode } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(setupDetail(for: mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.14),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func setupDetail(for mode: SidebarViewMode) -> String {
        switch mode {
        case .basic: "Stable updates and essential navigation."
        case .advanced: "Adds developer tools, prereleases, dependencies, and diagnostics."
        }
    }
}

@MainActor
private final class SetupViewState: ObservableObject {
    @Published var profile: SetupProfile = .applications
    @Published var sidebarViewMode: SidebarViewMode = .basic
}
