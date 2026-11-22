import Foundation

/// Test settings live in a temp folder for each test run instead of
/// ~/Library/Preferences. There, every test left a plist behind: `removePersistentDomain`
/// empties a domain, but the preferences daemon writes its file back afterwards.
enum TestDefaults {
    /// An absolute path as the domain name makes UserDefaults store it at "<path>.plist".
    static func domain(_ name: String) -> String { directory + "/" + name }

    private static let directory: String = {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("UpkeepTestDefaults", isDirectory: true)
        // Clear folders left by earlier runs whose process has exited.
        for entry in (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? [] {
            guard let pid = Int32(entry), pid != getpid(), kill(pid, 0) != 0 else { continue }
            try? fileManager.removeItem(at: root.appendingPathComponent(entry))
        }
        let directory = root.appendingPathComponent(String(getpid()), isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }()
}

extension UserDefaults {
    /// A throwaway settings store for one test, kept out of ~/Library/Preferences.
    convenience init?(testSuiteName name: String) {
        self.init(suiteName: TestDefaults.domain(name))
    }

    func removeTestDomain(forName name: String) {
        removePersistentDomain(forName: TestDefaults.domain(name))
    }
}
