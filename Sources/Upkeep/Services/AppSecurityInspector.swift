import Combine
import Foundation

struct AppDeclaredPermission: Identifiable, Hashable, Sendable {
    let title: String
    let systemImage: String
    var id: String { title }
}

struct AppSecurityReport: Equatable, Sendable {
    let permissions: [AppDeclaredPermission]
    let sandboxed: Bool?
    let hardenedRuntime: Bool?
    let signatureValid: Bool?
    let signingIdentity: String?
    let teamIdentifier: String?
    let gatekeeper: String
    let notarization: String
    let architectures: [String]
    let quarantine: Bool
    let minimumSystemVersion: String?
    let bundleType: String?
    let fileSize: Int64?
}

enum AppSecurityInspector {
    static func inspect(_ app: InstalledApp) async -> AppSecurityReport {
        await Task.detached(priority: .utility) { inspectSynchronously(app) }.value
    }

    static func declaredPermissions(
        info: [String: Any],
        entitlements: [String: Any]
    ) -> [AppDeclaredPermission] {
        let privacyKeys: [(String, String, String)] = [
            ("NSAppleEventsUsageDescription", "Automation", "gearshape.2.fill"),
            ("NSBluetoothAlwaysUsageDescription", "Bluetooth", "wave.3.right"),
            ("NSBluetoothPeripheralUsageDescription", "Bluetooth", "wave.3.right"),
            ("NSCalendarsUsageDescription", "Calendars", "calendar"),
            ("NSCameraUsageDescription", "Camera", "camera.fill"),
            ("NSContactsUsageDescription", "Contacts", "person.crop.circle.fill"),
            ("NSLocationUsageDescription", "Location", "location.fill"),
            ("NSLocationAlwaysUsageDescription", "Location", "location.fill"),
            ("NSLocationWhenInUseUsageDescription", "Location", "location.fill"),
            ("NSAppleMusicUsageDescription", "Media & Apple Music", "music.note"),
            ("NSMicrophoneUsageDescription", "Microphone", "mic.fill"),
            ("NSPhotoLibraryUsageDescription", "Photos", "photo.fill"),
            ("NSPhotoLibraryAddUsageDescription", "Photos", "photo.fill"),
            ("NSRemindersUsageDescription", "Reminders", "checklist"),
            ("NSSpeechRecognitionUsageDescription", "Speech Recognition", "waveform")
        ]
        var permissions = privacyKeys.compactMap { key, title, image -> AppDeclaredPermission? in
            guard info[key] != nil else { return nil }
            return AppDeclaredPermission(title: title, systemImage: image)
        }
        let entitlementPermissions: [(String, String, String)] = [
            ("com.apple.security.automation.apple-events", "Automation", "gearshape.2.fill"),
            ("com.apple.security.device.camera", "Camera", "camera.fill"),
            ("com.apple.security.device.microphone", "Microphone", "mic.fill"),
            ("com.apple.security.personal-information.addressbook", "Contacts", "person.crop.circle.fill"),
            ("com.apple.security.personal-information.calendars", "Calendars", "calendar"),
            ("com.apple.security.personal-information.location", "Location", "location.fill"),
            ("com.apple.security.personal-information.photos-library", "Photos", "photo.fill"),
            ("com.apple.security.files.user-selected.read-only", "User Selected Files", "doc.badge.plus"),
            ("com.apple.security.files.user-selected.read-write", "User Selected Files", "doc.badge.plus")
        ]
        for (key, title, image) in entitlementPermissions where entitlementIsEnabled(entitlements[key]) {
            permissions.append(AppDeclaredPermission(title: title, systemImage: image))
        }
        return Dictionary(grouping: permissions, by: \.title)
            .compactMap { $0.value.first }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func inspectSynchronously(_ app: InstalledApp) -> AppSecurityReport {
        let info = Bundle(url: app.url)?.infoDictionary ?? [:]
        let codesignDetails = command("/usr/bin/codesign", ["-dvvv", "--entitlements", ":-", "--xml", app.url.path])
        let entitlements = plistDictionary(in: codesignDetails.output) ?? [:]
        let signature = command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.url.path])
        let assessment = command("/usr/sbin/spctl", ["-a", "-vv", "--type", "execute", app.url.path])
        let quarantine = command("/usr/bin/xattr", ["-p", "com.apple.quarantine", app.url.path]).status == 0
        let architectures = AppArchitectureInspector.architectures(at: app.url, info: info)
        let authority = lines(in: codesignDetails.output, prefix: "Authority=").first
            ?? lines(in: assessment.output, prefix: "origin=").first
        let team = lines(in: codesignDetails.output, prefix: "TeamIdentifier=").first
        let assessmentSource = lines(in: assessment.output, prefix: "source=").first ?? "Not reported"
        let notarization: String
        if assessmentSource.localizedCaseInsensitiveContains("notarized") { notarization = "Notarized" }
        else if assessmentSource.localizedCaseInsensitiveContains("app store") { notarization = "App Store" }
        else { notarization = "Not reported" }

        return AppSecurityReport(
            permissions: declaredPermissions(info: info, entitlements: entitlements),
            sandboxed: boolValue(entitlements["com.apple.security.app-sandbox"]),
            hardenedRuntime: codesignDetails.output.localizedCaseInsensitiveContains("runtime"),
            signatureValid: signature.status == 0,
            signingIdentity: authority,
            teamIdentifier: team,
            gatekeeper: assessment.status == 0 ? "Accepted" : "Not accepted",
            notarization: notarization,
            architectures: architectures,
            quarantine: quarantine,
            minimumSystemVersion: info["LSMinimumSystemVersion"] as? String,
            bundleType: info["CFBundlePackageType"] as? String,
            fileSize: allocatedSize(of: app.url)
        )
    }

    private static func entitlementIsEnabled(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        return value != nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let bool = value as? Bool { return bool }
        return true
    }

    private static func plistDictionary(in text: String) -> [String: Any]? {
        guard let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex)
        else { return nil }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let data = xml.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return object as? [String: Any]
    }

    private static func lines(in text: String, prefix: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let value = String(line).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix(prefix) else { return nil }
            return String(value.dropFirst(prefix.count))
        }
    }

    private static func allocatedSize(of url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func command(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return (-1, "") }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

@MainActor
final class AppSecurityInspectionModel: ObservableObject {
    @Published private(set) var report: AppSecurityReport?

    func load(_ app: InstalledApp) async {
        report = nil
        report = await AppSecurityInspector.inspect(app)
    }
}
