import SwiftUI

struct ItemCheckStatus: View {
    let isRefreshing: Bool
    let lastChecked: Date?

    var body: some View {
        HStack(spacing: 6) {
            if isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Refreshing…")
            } else if let lastChecked {
                Image(systemName: "clock")
                Text("Last checked")
                Text(lastChecked, style: .relative)
            } else {
                Image(systemName: "clock.badge.questionmark")
                Text("Not checked yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct AppPermissionsSection: View {
    let report: AppSecurityReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions").font(.headline)
            if let report {
                if report.permissions.isEmpty {
                    Text("No macOS privacy usage descriptions or sandbox privacy capabilities were declared by this app.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(report.permissions) { permission in
                            Label(permission.title, systemImage: permission.systemImage)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(.quaternary.opacity(0.5), in: Capsule())
                        }
                    }
                    Text("These are capabilities declared by the app. Actual access is controlled in System Settings → Privacy & Security.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Inspecting app declarations…").controlSize(.small)
            }
        }
    }
}

struct AppSecuritySection: View {
    let report: AppSecurityReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Security").font(.headline)
            if let report {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 13) {
                    GridRow { value("App Sandbox", boolean: report.sandboxed); value("Hardened Runtime", boolean: report.hardenedRuntime) }
                    GridRow { value("Signature", text: signatureText); value("Gatekeeper", text: report.gatekeeper) }
                    GridRow { value("Notarization", text: report.notarization); value("Quarantine", text: report.quarantine ? "Present" : "Not present") }
                    if let identity = report.signingIdentity { GridRow { value("Signed By", text: identity); value("Team", text: report.teamIdentifier ?? "Not declared") } }
                    if !report.architectures.isEmpty { GridRow { value("Architectures", text: report.architectures.joined(separator: ", ")); Color.clear } }
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            } else {
                ProgressView("Verifying signature and Gatekeeper assessment…").controlSize(.small)
            }
        }
    }

    private var signatureText: String {
        switch report?.signatureValid {
        case .some(true): "Valid"
        case .some(false): "Invalid"
        case .none: "Unavailable"
        }
    }

    private func value(_ title: String, boolean: Bool?) -> some View {
        value(title, text: boolean.map { $0 ? "Enabled" : "Disabled" } ?? "Not declared")
    }

    private func value(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.callout.weight(.medium)).lineLimit(2).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PackageSecurityExplanation: View {
    let manager: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Permissions").font(.headline)
                Text("Command-line packages do not declare macOS app privacy usage descriptions. Any access is governed by the host application that runs the package.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Security & Provenance").font(.headline)
                Label("Installed and updated through \(manager)", systemImage: "checkmark.shield")
                    .font(.callout.weight(.medium))
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                Text("Package-manager provenance is not the same as macOS code-signing or notarization. Review the package registry and publisher before installing updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
