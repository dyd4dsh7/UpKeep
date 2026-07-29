import Darwin
import Foundation

struct AppManagementPermissionCheck: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case allowed
        case denied
        case unavailable
    }

    let status: Status
    let targetAppName: String?
    let detail: String
    let checkedAt: Date
}

enum AppManagementPermissionChecker {
    static func check(using apps: [InstalledApp]) async -> AppManagementPermissionCheck {
        await Task.detached(priority: .userInitiated) {
            checkSynchronously(using: apps)
        }.value
    }

    static func status(forErrno code: Int32) -> AppManagementPermissionCheck.Status {
        code == EPERM || code == EACCES ? .denied : .unavailable
    }

    private static func checkSynchronously(
        using apps: [InstalledApp]
    ) -> AppManagementPermissionCheck {
        guard let target = apps.lazy.compactMap(probeTarget).first else {
            return AppManagementPermissionCheck(
                status: .unavailable,
                targetAppName: nil,
                detail: "Upkeep could not find an eligible Homebrew app for the access check.",
                checkedAt: Date()
            )
        }

        errno = 0
        let descriptor = Darwin.open(target.url.path, O_WRONLY | O_CLOEXEC)
        if descriptor >= 0 {
            Darwin.close(descriptor)
            return AppManagementPermissionCheck(
                status: .allowed,
                targetAppName: target.appName,
                detail: "macOS allowed Upkeep to open \(target.appName) for modification. No data was written.",
                checkedAt: Date()
            )
        }

        let code = errno
        let result = status(forErrno: code)
        let systemMessage = String(cString: strerror(code))
        return AppManagementPermissionCheck(
            status: result,
            targetAppName: target.appName,
            detail: result == .denied
                ? "macOS blocked Upkeep from modifying \(target.appName). Enable Upkeep in Privacy & Security → App Management."
                : "The App Management check could not finish: \(systemMessage).",
            checkedAt: Date()
        )
    }

    private static func probeTarget(for app: InstalledApp) -> (appName: String, url: URL)? {
        let url = app.url.appendingPathComponent("Contents/Info.plist")
        var information = stat()
        guard lstat(url.path, &information) == 0,
              information.st_uid == geteuid(),
              information.st_mode & S_IWUSR != 0,
              information.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) == 0
        else { return nil }
        return (app.name, url)
    }
}
