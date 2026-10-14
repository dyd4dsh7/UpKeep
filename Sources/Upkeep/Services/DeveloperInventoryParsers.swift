import Foundation

/// Pure inventory-format decoding; command execution belongs to scan adapters.
enum DeveloperInventoryParsers {
    static func parseGemInventory(_ installedOutput: String, outdatedOutput: String, executablePath: String) -> [DeveloperPackage] {
        let outdated = parseGemOutdated(outdatedOutput)
        let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+\((?:default:\s*)?([^,\)]+)"#, options: .anchorsMatchLines)
        return installedOutput.split(separator: "\n").compactMap { line -> DeveloperPackage? in
            let value = String(line)
            guard let match = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let nameRange = Range(match.range(at: 1), in: value), let versionRange = Range(match.range(at: 2), in: value)
            else { return nil }
            let name = String(value[nameRange]); let version = String(value[versionRange])
            return DeveloperPackage(name: name, currentVersion: version, latestVersion: outdated[name] ?? version, manager: .rubyGems, executablePath: executablePath)
        }
    }

    private static func parseGemOutdated(_ output: String) -> [String: String] {
        let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+\([^\s]+\s+<\s+([^\)]+)\)$"#, options: .anchorsMatchLines)
        return output.split(separator: "\n").reduce(into: [:]) { values, line in
            let value = String(line)
            guard let match = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let nameRange = Range(match.range(at: 1), in: value), let latestRange = Range(match.range(at: 2), in: value)
            else { return }
            values[String(value[nameRange])] = String(value[latestRange])
        }
    }


    static func parseExtensionInventory(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").reduce(into: [:]) { values, line in
            guard let separator = line.lastIndex(of: "@") else { return }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(line)
            let textSeparator = text.index(text.startIndex, offsetBy: line.distance(from: line.startIndex, to: separator))
            let version = String(text[text.index(after: textSeparator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !version.isEmpty { values[name] = version }
        }
    }

    static func parseYarnGlobalPackages(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        var packages: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? JSONDecoder().decode(YarnListEvent.self, from: lineData),
                  event.type == "tree" else { continue }
            for tree in event.data?.trees ?? [] {
                guard let separator = tree.name.lastIndex(of: "@") else { continue }
                let name = String(tree.name[..<separator])
                let version = String(tree.name[tree.name.index(after: separator)...])
                if !name.isEmpty, !version.isEmpty { packages[name] = version }
            }
        }
        return packages
    }

    static func parseSimpleToolList(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
            let parts = rawLine.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { return }
            let name = String(parts[0])
            let version = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if version.first?.isNumber == true { values[name] = version }
        }
    }

    static func parseUVPythonDirectoryName(_ name: String) -> (implementation: String, version: String, minor: String)? {
        let regex = try? NSRegularExpression(pattern: #"^(cpython|pypy)-(\d+\.\d+\.\d+)(?:[-+].*)?$"#, options: .caseInsensitive)
        guard let match = regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let implementationRange = Range(match.range(at: 1), in: name),
              let versionRange = Range(match.range(at: 2), in: name) else { return nil }
        let version = String(name[versionRange])
        let components = version.split(separator: ".")
        guard components.count >= 2 else { return nil }
        let implementation = String(name[implementationRange]).lowercased() == "pypy" ? "PyPy" : "CPython"
        return (implementation, version, components.prefix(2).joined(separator: "."))
    }

    static func parseUVPythonList(_ data: Data, matchingMinor minor: String) -> [String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(pattern: #"(?:cpython|pypy)-(\d+\.\d+\.\d+)"#, options: .caseInsensitive)
        let versions = output.split(separator: "\n").compactMap { rawLine -> String? in
            let line = String(rawLine)
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            let version = String(line[range])
            return version.hasPrefix(minor + ".") ? version : nil
        }
        return VersionComparator.sortedNewestFirst(Set(versions))
    }

    static func parseRustupCheck(_ data: Data) -> [(name: String, current: String, latest: String)] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let versionPattern = #"\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?"#
        let regex = try? NSRegularExpression(pattern: versionPattern)
        return output.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard let divider = line.range(of: " - "), line.contains(":") else { return nil }
            let name = String(line[..<divider.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = regex?.matches(in: line, range: NSRange(line.startIndex..., in: line)) ?? []
            let versions = matches.compactMap { Range($0.range, in: line).map { String(line[$0]) } }
            guard let current = versions.first else { return nil }
            return (name, current, versions.count > 1 ? versions.last! : current)
        }
    }

    static func parseGitHubExtensionList(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        var values: [String: String] = [:]
        for rawLine in output.split(separator: "\n") {
            let fields = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let repository = fields.first(where: { $0.contains("/") }) else { continue }
            let version = fields.reversed().first(where: {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).first?.isNumber == true
            })?.trimmingCharacters(in: CharacterSet(charactersIn: "vV")) ?? "unknown"
            values[repository] = version
        }
        return values
    }

    static func parseGitHubExtensionUpdates(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(pattern: #"([\w.-]+/[\w.-]+).*?(?:to|->)\s+v?([0-9][0-9A-Za-z.+-]*)"#, options: .caseInsensitive)
        return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
            let line = String(rawLine)
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let repositoryRange = Range(match.range(at: 1), in: line),
                  let versionRange = Range(match.range(at: 2), in: line) else { return }
            values[String(line[repositoryRange])] = String(line[versionRange])
        }
    }

    static func parseGoBuildInfo(_ data: Data) -> GoInstalledTool? {
        let lines = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
        let command = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("path\t") })?
            .split(separator: "\t", maxSplits: 1).last.map(String.init)
        let moduleFields = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("mod\t") })?
            .split(separator: "\t").map(String.init)
        guard let command, let moduleFields, moduleFields.count >= 3 else { return nil }
        let version = moduleFields[2].trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard version.first?.isNumber == true else { return nil }
        return GoInstalledTool(command: command, module: moduleFields[1], version: version)
    }

    static func parseGoRuntimeVersion(_ data: Data) -> String? {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(pattern: #"\bgo(\d+\.\d+(?:\.\d+)?)\b"#)
        guard let match = regex?.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }

    static func parseDotnetToolList(_ data: Data) -> [String: String] {
        if let root = try? JSONDecoder().decode(DotnetToolList.self, from: data) {
            return root.data.reduce(into: [:]) { values, tool in values[tool.packageId] = tool.version }
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").reduce(into: [:]) { values, rawLine in
            let fields = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[1].first?.isNumber == true else { return }
            values[fields[0]] = fields[1]
        }
    }

    static func parseMacPortsOutdated(_ data: Data) -> [(name: String, current: String, latest: String)] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(pattern: #"^\s*(\S+)\s+@?([^\s]+).*?<\s+@?([^\s]+)"#, options: .anchorsMatchLines)
        return output.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line),
                  let current = Range(match.range(at: 2), in: line),
                  let latest = Range(match.range(at: 3), in: line) else { return nil }
            return (String(line[name]), stripPackageRevision(String(line[current])), stripPackageRevision(String(line[latest])))
        }
    }

    static func parseMacPortsInstalled(_ data: Data) -> [(name: String, version: String)] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(pattern: #"^\s*(\S+)\s+@([^\s]+)"#, options: .anchorsMatchLines)
        return output.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line),
                  let version = Range(match.range(at: 2), in: line) else { return nil }
            return (String(line[name]), stripPackageRevision(String(line[version])))
        }
    }

    static func parseNixDryRun(_ data: Data) -> [(name: String, current: String, latest: String, selector: String)] {
        let output = String(data: data, encoding: .utf8) ?? ""
        let regex = try? NSRegularExpression(
            pattern: #"(?:upgrade|upgrading)\s+['\"]?([^'\"\s]+)['\"]?.*?from\s+['\"]?v?([^'\"\s]+)['\"]?\s+(?:to|->)\s+['\"]?v?([^'\"\s]+)"#,
            options: .caseInsensitive
        )
        let arrowRegex = try? NSRegularExpression(
            pattern: #"^\s*['\"]?([^:'\"\s]+)['\"]?\s*:\s*['\"]?v?([0-9][^'\"\s]*)['\"]?\s*(?:->|→)\s*['\"]?v?([0-9][^'\"\s]*)"#,
            options: .caseInsensitive
        )
        return output.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
                ?? arrowRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            guard let match,
                  let selectorRange = Range(match.range(at: 1), in: line),
                  let currentRange = Range(match.range(at: 2), in: line),
                  let latestRange = Range(match.range(at: 3), in: line) else { return nil }
            let selector = String(line[selectorRange])
            let name = selector.split(separator: "#").last.map(String.init) ?? selector
            return (name, String(line[currentRange]), String(line[latestRange]), selector)
        }
    }

    static func parseNixProfileJSON(_ data: Data) -> [(name: String, version: String, selector: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let elements = (root["elements"] as? [String: Any]) ?? root
        return elements.compactMap { selector, rawValue in
            guard let value = rawValue as? [String: Any] else { return nil }
            let storePaths = value["storePaths"] as? [String] ?? value["store-paths"] as? [String] ?? []
            guard let storePath = storePaths.first,
                  let parsed = parseNixStorePath(storePath) else { return nil }
            return (parsed.name, parsed.version, selector)
        }
    }

    private static func parseNixStorePath(_ path: String) -> (name: String, version: String)? {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let withoutHash = fileName.split(separator: "-", maxSplits: 1).dropFirst().first.map(String.init) ?? fileName
        let regex = try? NSRegularExpression(pattern: #"^(.+)-([0-9][0-9A-Za-z.+_-]*)$"#)
        guard let match = regex?.firstMatch(in: withoutHash, range: NSRange(withoutHash.startIndex..., in: withoutHash)),
              let name = Range(match.range(at: 1), in: withoutHash),
              let version = Range(match.range(at: 2), in: withoutHash) else { return nil }
        return (String(withoutHash[name]), stripPackageRevision(String(withoutHash[version])))
    }

    static func parseGenericOutdatedJSON(_ data: Data) -> [(name: String, current: String, latest: String)] {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var results: [(String, String, String)] = []
        func visit(_ value: Any, hintedName: String? = nil) {
            if let dictionary = value as? [String: Any] {
                let name = (dictionary["name"] as? String) ?? (dictionary["tool"] as? String) ?? hintedName
                let current = (dictionary["current"] as? String) ?? (dictionary["version"] as? String)
                let latest = (dictionary["latest"] as? String) ?? (dictionary["new_version"] as? String)
                if let name, let current, let latest, current != latest { results.append((name, current, latest)) }
                for (key, child) in dictionary { visit(child, hintedName: key) }
            } else if let array = value as? [Any] {
                for child in array { visit(child, hintedName: hintedName) }
            }
        }
        visit(value)
        var seen = Set<String>()
        return results.filter { seen.insert("\($0.0):\($0.1):\($0.2)").inserted }
    }

    static func parseMiseInstalledJSON(_ data: Data) -> [(name: String, version: String)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var values: [(String, String)] = []
        for (name, rawEntries) in root {
            let entries = rawEntries as? [[String: Any]] ?? []
            for entry in entries {
                guard let version = entry["version"] as? String, !version.isEmpty else { continue }
                values.append((name, version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))))
            }
        }
        return values
    }

    static func parseASDFCurrent(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").reduce(into: [:]) { values, line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[1] != "______", fields[1] != "No" else { return }
            values[fields[0]] = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        }
    }

    static func parseVoltaList(_ data: Data) -> [String: String] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").reduce(into: [:]) { values, line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let token = fields.first(where: { $0.contains("@") }),
                  let separator = token.lastIndex(of: "@") else { return }
            let name = String(token[..<separator])
            let version = String(token[token.index(after: separator)...]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if !name.isEmpty, version.first?.isNumber == true, values[name] == nil { values[name] = version }
        }
    }

    static func parseFNMList(_ data: Data) -> [(version: String, isDefault: Bool)] {
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let versionToken = fields.first(where: { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*vV" )).first?.isNumber == true }) else { return nil }
            return (
                versionToken.trimmingCharacters(in: CharacterSet(charactersIn: "*vV")),
                line.contains("default") || line.hasPrefix("*")
            )
        }
    }

    private static func stripPackageRevision(_ value: String) -> String {
        value.split(separator: "_").first.map(String.init) ?? value
    }


    private struct DotnetToolList: Decodable {
        let data: [Tool]
        struct Tool: Decodable {
            let packageId: String
            let version: String
            enum CodingKeys: String, CodingKey { case packageId = "packageId"; case version }
        }
    }

    private struct YarnListEvent: Decodable {
        let type: String
        let data: TreeData?
        struct TreeData: Decodable { let trees: [Tree] }
        struct Tree: Decodable { let name: String }
    }
}
