import Foundation

enum AppRestoreTransaction {
    /// Keep the installed app intact until the replacement is fully copied and validated.
    /// If the final rename fails, put the original back before reporting the failure.
    static func perform(
        backup: URL, installed: URL, staged: URL, displaced: URL,
        exists: (URL) -> Bool,
        copy: (URL, URL) throws -> Void,
        validate: (URL) throws -> Void,
        move: (URL, URL) throws -> Void
    ) throws -> Bool {
        try copy(backup, staged)
        try validate(staged)
        let hadInstalledApp = exists(installed)
        if hadInstalledApp { try move(installed, displaced) }
        do {
            try move(staged, installed)
        } catch {
            if hadInstalledApp {
                do { try move(displaced, installed) }
                catch {
                    throw RestoreError.recoveryRequired(displaced.path, error.localizedDescription)
                }
            }
            throw error
        }
        return hadInstalledApp
    }

    enum RestoreError: LocalizedError {
        case invalidBackup
        case recoveryRequired(String, String)

        var errorDescription: String? {
            switch self {
            case .invalidBackup: "The backup does not contain the expected app and version. The installed app was not changed."
            case let .recoveryRequired(path, message):
                "Restore could not finish. Your previous app is preserved at \(path). Move it back to its original location. \(message)"
            }
        }
    }
}
