import Foundation

/// Path ownership only; never launches a manager or reads executable contents.
func runtimeEnvironmentOwners(for executable: String,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> Set<String> {
    let paths = [executable, URL(fileURLWithPath: executable).resolvingSymlinksInPath().standardizedFileURL.path]
    let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    func nonempty(_ key: String) -> String? {
        environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }
    var roots: [(String, String, [String])] = [
        ("asdf", nonempty("ASDF_DATA_DIR") ?? "\(home)/.asdf", ["shims", "installs"]),
        ("mise", nonempty("MISE_DATA_DIR") ?? "\(nonempty("XDG_DATA_HOME") ?? "\(home)/.local/share")/mise", ["shims", "installs"]),
        ("volta", nonempty("VOLTA_HOME") ?? "\(home)/.volta", ["bin", "tools"])
    ]
    if let fnmRoot = nonempty("FNM_DIR") { roots.append(("fnm", fnmRoot, ["node-versions"])) }
    var owners = Set<String>()
    for (owner, root, directories) in roots {
        let rootURL = root.hasPrefix("/") ? URL(fileURLWithPath: root)
            : URL(fileURLWithPath: root, relativeTo: developerCommandWorkingDirectory(base: environment))
        let canonical = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        if paths.contains(where: { path in directories.contains { path.hasPrefix("\(canonical)/\($0)/") } }) {
            owners.insert(owner)
        }
    }
    // Retain scanner-recognized installations outside the current HOME too.
    let markers: [(String, [String])] = [
        ("asdf", ["/.asdf/shims/", "/.asdf/installs/"]),
        ("mise", ["/mise/shims/", "/mise/installs/"]),
        ("volta", ["/.volta/bin/", "/.volta/tools/"]),
        ("fnm", ["/fnm/node-versions/"])
    ]
    for (owner, markers) in markers where paths.contains(where: { path in markers.contains { path.contains($0) } }) {
        owners.insert(owner)
    }
    return owners
}
