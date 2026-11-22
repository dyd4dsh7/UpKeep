import CryptoKit
import Foundation

struct LocalModelClient: Sendable {
    struct Report: Sendable {
        let models: [LocalLLMModel]
        let warnings: [String]
        let failedModelIDs: Set<String>
        let failedRuntimes: Set<LocalModelRuntime>
        var warningRuntimes: [String: Set<LocalModelRuntime>] = [:]

        var scanWarnings: [ScanWarning] {
            warnings.map { ScanWarning(source: .localModels,
                itemNames: warningRuntimes[$0]?.map(\.rawValue) ?? [], message: $0) }
        }

        static let empty = Report(models: [], warnings: [], failedModelIDs: [], failedRuntimes: [])
    }

    func scan() async -> Report {
        await scan(progress: nil)
    }

    func scan(progress: LocalModelScanProgressReporter?) async -> Report {
        await withTaskGroup(of: ModelRuntimeScanResult.self) { group in
            group.addTask { await scanOllama() }
            group.addTask { await scanLMStudio() }
            group.addTask { await scanHuggingFaceCache() }
            var results: [ModelRuntimeScanResult] = []
            for await result in group {
                if let progress { await progress(report(from: [result]), [result.runtime]) }
                results.append(result)
            }
            return report(from: results)
        }
    }

    func scan(runtime: LocalModelRuntime) async -> Report {
        let result: ModelRuntimeScanResult
        switch runtime {
        case .ollama: result = await scanOllama()
        case .lmStudio: result = await scanLMStudio()
        case .huggingFace: result = await scanHuggingFaceCache()
        }
        return report(from: [result])
    }

    private func report(from results: [ModelRuntimeScanResult]) -> Report {
        let models = results.flatMap(\.models).sorted {
            if $0.runtime != $1.runtime { return $0.runtime.rawValue < $1.runtime.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var warningRuntimes: [String: Set<LocalModelRuntime>] = [:]
        for result in results {
            if let warning = result.warning { warningRuntimes[warning, default: []].insert(result.runtime) }
        }
        return Report(
            models: models,
            warnings: results.compactMap(\.warning),
            failedModelIDs: Set(results.flatMap(\.failedModelIDs)),
            failedRuntimes: Set(results.filter(\.runtimeFailed).map(\.runtime)),
            warningRuntimes: warningRuntimes
        )
    }

    func update(_ model: LocalLLMModel) async throws {
        switch model.runtime {
        case .ollama:
            guard let path = model.executablePath else { throw ModelError.runtimeUnavailable("Ollama") }
            try await run(URL(fileURLWithPath: path), ["pull", model.updateReference])
        case .lmStudio:
            guard let path = model.executablePath else { throw ModelError.runtimeUnavailable("LM Studio") }
            try await run(URL(fileURLWithPath: path), ["get", model.updateReference, "--yes"])
        case .huggingFace:
            guard let path = model.executablePath else { throw ModelError.runtimeUnavailable("The Hugging Face CLI (hf)") }
            // Refresh only the files already cached, at the repository's main revision.
            let files = huggingFaceCachedFiles(repository: model.updateReference)
            try await run(URL(fileURLWithPath: path), ["download", model.updateReference] + files)
        }
    }

    private func scanHuggingFaceCache() async -> ModelRuntimeScanResult {
        let executable = executable(named: "hf", extra: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hf").path
        ]) ?? executable(named: "huggingface-cli", extra: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/huggingface-cli").path
        ])
        let entries = huggingFaceCacheEntries(roots: huggingFaceCacheRoots())
        let results = await withTaskGroup(of: (LocalLLMModel, Bool).self) { group in
            for entry in entries {
                group.addTask {
                    let latest = await huggingFaceMainRevision(entry.repository)
                    return (LocalLLMModel(
                        id: "huggingface:\(entry.repository)", name: entry.repository, variant: nil,
                        runtime: .huggingFace, installedRevision: String(entry.revision.prefix(7)),
                        latestRevision: String((latest ?? entry.revision).prefix(7)),
                        sizeBytes: entry.sizeBytes, modifiedAt: entry.modifiedAt,
                        homepage: URL(string: "https://huggingface.co/\(entry.repository)"),
                        executablePath: executable, updateReference: entry.repository,
                        isOutdated: latest.map { $0 != entry.revision } ?? false
                    ), latest == nil)
                }
            }
            var models: [(LocalLLMModel, Bool)] = []
            for await model in group { models.append(model) }
            return models
        }
        let failedIDs = results.filter { $0.1 }.map { $0.0.id }
        return ModelRuntimeScanResult(
            runtime: .huggingFace,
            models: results.map { $0.0 },
            failedModelIDs: failedIDs,
            runtimeFailed: false,
            warning: failedIDs.isEmpty ? nil : "Hugging Face checks failed for \(failedIDs.count) cached model\(failedIDs.count == 1 ? "" : "s")."
        )
    }

    private func scanOllama() async -> ModelRuntimeScanResult {
        let executable = executable(named: "ollama", extra: [
            "/Applications/Ollama.app/Contents/Resources/ollama",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/ollama").path
        ])
        var rows = ollamaRowsFromDisk(modelRoots: ollamaModelRoots())
        if rows.isEmpty, let executable {
            let output = await capture(URL(fileURLWithPath: executable), ["list"])
            if output.status == 0 {
                rows = parseOllamaList(String(decoding: output.data, as: UTF8.self))
            } else {
                return ModelRuntimeScanResult(
                    runtime: .ollama, models: [], failedModelIDs: [], runtimeFailed: true,
                    warning: "Ollama inventory failed: \(commandMessage(output))"
                )
            }
        }
        let results = await withTaskGroup(of: (LocalLLMModel, Bool).self) { group in
            for row in rows {
                group.addTask {
                    let remote = await ollamaManifest(for: row.name)
                    let latest = remote?.digest ?? row.digest
                    let outdated = remote.map { !digest($0.digest, matches: row.digest) } ?? false
                    return (LocalLLMModel(
                        id: "ollama:\(row.name)", name: row.name, variant: ollamaTag(row.name),
                        runtime: .ollama, installedRevision: shortDigest(row.digest),
                        latestRevision: shortDigest(latest), sizeBytes: row.sizeBytes,
                        modifiedAt: row.modifiedAt, homepage: ollamaHomepage(row.name),
                        executablePath: executable, updateReference: row.name, isOutdated: outdated
                    ), remote == nil)
                }
            }
            var models: [(LocalLLMModel, Bool)] = []
            for await model in group { models.append(model) }
            return models
        }
        let failedIDs = results.filter { $0.1 }.map { $0.0.id }
        return ModelRuntimeScanResult(
            runtime: .ollama,
            models: results.map { $0.0 },
            failedModelIDs: failedIDs,
            runtimeFailed: false,
            warning: failedIDs.isEmpty ? nil : "Ollama registry checks failed for \(failedIDs.count) model\(failedIDs.count == 1 ? "" : "s")."
        )
    }

    private func scanLMStudio() async -> ModelRuntimeScanResult {
        let executable = executable(named: "lms", extra: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lmstudio/bin/lms").path
        ])
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let roots = lmStudioModelRoots()
        var seenRelativePaths = Set<String>()
        let files = roots.flatMap { root -> [(root: URL, file: URL)] in
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter {
                let ext = $0.pathExtension.lowercased()
                return ["gguf", "safetensors", "bin"].contains(ext) && !$0.lastPathComponent.hasPrefix(".")
            }.filter {
                // Configured storage takes precedence over legacy folders. Model IDs
                // describe the repository/file, so do not emit that ID twice.
                seenRelativePaths.insert(String($0.path.dropFirst(root.path.count + 1))).inserted
            }.map { (root, $0) }
        }
        let results = await withTaskGroup(of: (LocalLLMModel, Bool)?.self) { group in
            for entry in files {
                group.addTask {
                    let root = entry.root, file = entry.file
                    let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                    let parts = relative.split(separator: "/").map(String.init)
                    guard parts.count >= 3 else { return nil }
                    let publisher = parts[0], repository = parts[1]
                    let repositoryID = "\(publisher)/\(repository)"
                    let values = try? file.resourceValues(forKeys: Set(keys))
                    let modified = values?.contentModificationDate
                    let remoteModified = await huggingFaceFileModifiedAt(repositoryID, filename: file.lastPathComponent)
                    let isOutdated = remoteModified.map { remote in
                        guard let modified else { return false }
                        return remote.timeIntervalSince(modified) > 300
                    } ?? false
                    let variant = file.deletingPathExtension().lastPathComponent
                    let quantization = lmStudioQuantization(variant)
                    return (LocalLLMModel(
                        id: "lmstudio:\(relative)", name: repositoryID, variant: variant,
                        runtime: .lmStudio, installedRevision: revisionDate(modified),
                        latestRevision: revisionDate(remoteModified ?? modified),
                        sizeBytes: values?.fileSize.map(Int64.init), modifiedAt: modified,
                        homepage: URL(string: "https://huggingface.co/\(repositoryID)"),
                        executablePath: executable,
                        updateReference: quantization.map { "\(repositoryID)@\($0)" } ?? repositoryID,
                        isOutdated: isOutdated
                    ), remoteModified == nil)
                }
            }
            var models: [(LocalLLMModel, Bool)] = []
            for await model in group { if let model { models.append(model) } }
            return models
        }
        let failedIDs = results.filter { $0.1 }.map { $0.0.id }
        return ModelRuntimeScanResult(
            runtime: .lmStudio,
            models: results.map { $0.0 },
            failedModelIDs: failedIDs,
            runtimeFailed: false,
            warning: failedIDs.isEmpty ? nil : "Hugging Face checks failed for \(failedIDs.count) model file\(failedIDs.count == 1 ? "" : "s")."
        )
    }
}

private struct ModelRuntimeScanResult: Sendable {
    let runtime: LocalModelRuntime
    let models: [LocalLLMModel]
    let failedModelIDs: [String]
    let runtimeFailed: Bool
    let warning: String?
}

private func commandMessage(_ result: (data: Data, status: Int32)) -> String {
    let output = String(data: result.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return output?.isEmpty == false ? output! : "command exited with status \(result.status)"
}

private func ollamaModelRoots() -> [URL] {
    var roots: [URL] = []
    if let custom = ProcessInfo.processInfo.environment["OLLAMA_MODELS"], !custom.isEmpty {
        roots.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true))
    }
    roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models", isDirectory: true))
    return uniqueExistingDirectories(roots)
}

private func lmStudioModelRoots() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    var roots: [URL] = []
    let settings = home.appendingPathComponent(".lmstudio/settings.json")
    if let data = try? Data(contentsOf: settings),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let configured = object["downloadsFolder"] as? String, !configured.isEmpty {
        roots.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true))
    }
    roots += [
        home.appendingPathComponent(".lmstudio/models", isDirectory: true),
        home.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
        home.appendingPathComponent("Library/Application Support/LM Studio/models", isDirectory: true)
    ]
    return uniqueExistingDirectories(roots)
}

/// huggingface_hub's cache: HF_HUB_CACHE, then HF_HOME/hub, then
/// ~/.cache/huggingface/hub. GUI apps rarely inherit these variables.
func huggingFaceCacheRoots(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
    func path(_ value: String) -> URL { URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true) }
    var roots: [URL] = []
    if let cache = environment["HF_HUB_CACHE"] ?? environment["HUGGINGFACE_HUB_CACHE"], !cache.isEmpty {
        roots.append(path(cache))
    }
    if let home = environment["HF_HOME"], !home.isEmpty { roots.append(path(home).appendingPathComponent("hub", isDirectory: true)) }
    if let xdg = environment["XDG_CACHE_HOME"], !xdg.isEmpty {
        roots.append(path(xdg).appendingPathComponent("huggingface/hub", isDirectory: true))
    }
    roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub", isDirectory: true))
    return uniqueExistingDirectories(roots)
}

struct HuggingFaceCacheEntry: Equatable, Sendable {
    let repository: String
    let revision: String
    let sizeBytes: Int64?
    let modifiedAt: Date?
}

/// Model repositories that track `main`. Datasets, spaces, and models
/// downloaded at a pinned revision (no refs/main) are not checked.
func huggingFaceCacheEntries(roots: [URL]) -> [HuggingFaceCacheEntry] {
    let fileManager = FileManager.default
    var seen = Set<String>()
    return roots.flatMap { root -> [HuggingFaceCacheEntry] in
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            let name = folder.lastPathComponent
            guard name.hasPrefix("models--") else { return nil }
            let parts = name.dropFirst("models--".count).components(separatedBy: "--")
            guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            let repository = parts.joined(separator: "/")
            let ref = folder.appendingPathComponent("refs/main")
            guard seen.insert(repository).inserted,
                  let revision = (try? String(contentsOf: ref, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  revision.count == 40, revision.allSatisfy(\.isHexDigit),
                  fileManager.fileExists(atPath: folder.appendingPathComponent("snapshots/\(revision)").path)
            else { return nil }
            let modified = (try? ref.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return HuggingFaceCacheEntry(
                repository: repository, revision: revision,
                sizeBytes: directorySize(folder.appendingPathComponent("blobs", isDirectory: true)),
                modifiedAt: modified
            )
        }
    }
}

/// Relative paths in the cached main snapshot, so an update refreshes the same files.
func huggingFaceCachedFiles(repository: String, roots: [URL] = huggingFaceCacheRoots()) -> [String] {
    let folderName = "models--" + repository.replacingOccurrences(of: "/", with: "--")
    for root in roots {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        guard let revision = (try? String(contentsOf: folder.appendingPathComponent("refs/main"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
        let snapshot = folder.appendingPathComponent("snapshots/\(revision)", isDirectory: true).standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: snapshot, includingPropertiesForKeys: nil) else { continue }
        return enumerator.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
            .map { String($0.standardizedFileURL.path.dropFirst(snapshot.path.count + 1)) }
            .sorted()
    }
    return []
}

private func directorySize(_ url: URL) -> Int64? {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return nil }
    return enumerator.compactMap { $0 as? URL }.reduce(into: Int64(0)) { total, file in
        guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { return }
        total += Int64(values.fileSize ?? 0)
    }
}

private func huggingFaceMainRevision(_ repository: String) async -> String? {
    guard let encoded = repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "https://huggingface.co/api/models/\(encoded)/revision/main") else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
    struct Revision: Decodable { let sha: String }
    guard let (data, response) = try? await PublisherHTTPClient.data(for: request),
          200..<300 ~= response.statusCode,
          let revision = try? JSONDecoder().decode(Revision.self, from: data),
          revision.sha.count == 40
    else { return nil }
    return revision.sha
}

private func uniqueExistingDirectories(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    return urls.filter {
        let path = $0.standardizedFileURL.path
        return seen.insert(path).inserted && FileManager.default.fileExists(atPath: path)
    }
}

struct OllamaRow: Sendable {
    let name: String
    let digest: String
    let sizeBytes: Int64?
    let modifiedAt: Date?
}

private struct OllamaManifest: Sendable { let digest: String }

private struct OllamaDiskManifest: Decodable {
    let layers: [Layer]
    struct Layer: Decodable { let size: Int64? }
}

func ollamaRowsFromDisk(modelRoots: [URL]) -> [OllamaRow] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
    var rowsByName: [String: OllamaRow] = [:]
    for modelRoot in modelRoots {
        let manifests = modelRoot.appendingPathComponent("manifests", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: keys) else { continue }
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let data = try? Data(contentsOf: file) else { continue }
            let relative = file.path.replacingOccurrences(of: manifests.path + "/", with: "")
            let components = relative.split(separator: "/").map(String.init)
            guard components.count >= 4 else { continue }
            let repositoryParts = Array(components.dropFirst().dropLast())
            let repository = repositoryParts.first == "library"
                ? repositoryParts.dropFirst().joined(separator: "/")
                : repositoryParts.joined(separator: "/")
            guard !repository.isEmpty, let tag = components.last else { continue }
            let name = "\(repository):\(tag)"
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let manifest = try? JSONDecoder().decode(OllamaDiskManifest.self, from: data)
            let size = manifest?.layers.compactMap(\.size).reduce(0, +)
            let row = OllamaRow(
                name: name,
                digest: "sha256:\(hash)",
                sizeBytes: size,
                modifiedAt: values.contentModificationDate
            )
            if (rowsByName[name]?.modifiedAt ?? .distantPast) < (row.modifiedAt ?? .distantPast) {
                rowsByName[name] = row
            }
        }
    }
    return rowsByName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

private func parseOllamaList(_ output: String) -> [OllamaRow] {
    output.split(separator: "\n").dropFirst().compactMap { line in
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 2 else { return nil }
        let size = fields.count >= 4 ? byteCount(fields[2], unit: fields[3]) : nil
        return OllamaRow(name: fields[0], digest: fields[1], sizeBytes: size, modifiedAt: nil)
    }
}

private func ollamaManifest(for model: String) async -> OllamaManifest? {
    let parsed = ollamaReference(model)
    guard let url = URL(string: "https://registry.ollama.ai/v2/\(parsed.repository)/manifests/\(parsed.tag)") else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json", forHTTPHeaderField: "Accept")
    guard var (data, response) = try? await PublisherHTTPClient.data(for: request) else { return nil }
    var http = response

    if http.statusCode == 401,
       let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate"),
       let tokenURL = ollamaTokenURL(from: challenge, repository: parsed.repository),
       let (tokenData, tokenResponse) = try? await PublisherHTTPClient.data(for: URLRequest(url: tokenURL)),
       tokenResponse.statusCode == 200,
       let token = (try? JSONDecoder().decode(OllamaToken.self, from: tokenData))?.token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let authenticated = try? await PublisherHTTPClient.data(for: request) else { return nil }
        let authenticatedHTTP = authenticated.1
        (data, response) = authenticated
        http = authenticatedHTTP
    }

    guard 200..<300 ~= http.statusCode else { return nil }
    let digest = http.value(forHTTPHeaderField: "Docker-Content-Digest") ?? "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return OllamaManifest(digest: digest)
}

private struct OllamaToken: Decodable { let token: String }

func ollamaTokenURL(from challenge: String, repository: String) -> URL? {
    guard challenge.lowercased().hasPrefix("bearer ") else { return nil }
    let parameters = challenge.dropFirst("Bearer ".count).split(separator: ",").reduce(into: [String: String]()) { result, field in
        let pair = field.split(separator: "=", maxSplits: 1).map(String.init)
        guard pair.count == 2 else { return }
        result[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] = pair[1]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }
    guard let realm = parameters["realm"], var components = URLComponents(string: realm) else { return nil }
    var queryItems = components.queryItems ?? []
    if let service = parameters["service"] {
        queryItems.append(URLQueryItem(name: "service", value: service))
    }
    queryItems.append(URLQueryItem(
        name: "scope",
        value: parameters["scope"] ?? "repository:\(repository):pull"
    ))
    components.queryItems = queryItems
    return components.url
}

private func ollamaReference(_ value: String) -> (repository: String, tag: String) {
    var reference = value
    if reference.hasPrefix("registry.ollama.ai/") { reference.removeFirst("registry.ollama.ai/".count) }
    let slash = reference.lastIndex(of: "/")
    let colon = reference.lastIndex(of: ":")
    let hasTag = colon.map { slash == nil || $0 > slash! } ?? false
    let tag = hasTag ? String(reference[reference.index(after: colon!)...]) : "latest"
    let name = hasTag ? String(reference[..<colon!]) : reference
    return (name.contains("/") ? name : "library/\(name)", tag)
}

private func ollamaTag(_ value: String) -> String? {
    let parsed = ollamaReference(value)
    return parsed.tag
}

private func ollamaHomepage(_ value: String) -> URL? {
    let parsed = ollamaReference(value)
    let name = parsed.repository.replacingOccurrences(of: "library/", with: "")
    return URL(string: "https://ollama.com/library/\(name)")
}

private func digest(_ remote: String, matches local: String) -> Bool {
    let remoteValue = remote.replacingOccurrences(of: "sha256:", with: "")
    let localValue = local.replacingOccurrences(of: "sha256:", with: "")
    return remoteValue.hasPrefix(localValue) || localValue.hasPrefix(remoteValue)
}

private func shortDigest(_ value: String) -> String {
    String(value.replacingOccurrences(of: "sha256:", with: "").prefix(12))
}

func byteCount(_ value: String, unit: String) -> Int64? {
    guard let number = Double(value) else { return nil }
    let multiplier: Double = switch unit.uppercased() {
    case "KB": 1_000
    case "MB": 1_000_000
    case "GB": 1_000_000_000
    case "TB": 1_000_000_000_000
    default: 1
    }
    let bytes = number * multiplier
    guard bytes.isFinite, bytes >= 0, bytes < Double(Int64.max) else { return nil }
    return Int64(bytes)
}

private func huggingFaceFileModifiedAt(_ repository: String, filename: String) async -> Date? {
    guard let encoded = repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          var components = URLComponents(string: "https://huggingface.co/api/models/\(encoded)/tree/main") else { return nil }
    components.queryItems = [
        URLQueryItem(name: "recursive", value: "true"),
        URLQueryItem(name: "expand", value: "true"),
        URLQueryItem(name: "limit", value: "1000")
    ]
    guard let url = components.url else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Upkeep/0.9", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await PublisherHTTPClient.data(for: request),
          200..<300 ~= response.statusCode,
          let entries = try? JSONDecoder().decode([HuggingFaceTreeEntry].self, from: data),
          let value = entries.first(where: { URL(fileURLWithPath: $0.path).lastPathComponent == filename })?.lastCommit?.date
    else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private struct HuggingFaceTreeEntry: Decodable {
    let path: String
    let lastCommit: Commit?
    struct Commit: Decodable { let date: String }
}

private func revisionDate(_ value: Date?) -> String {
    guard let value else { return "Unknown" }
    return value.formatted(date: .abbreviated, time: .omitted)
}

private func lmStudioQuantization(_ filename: String) -> String? {
    let patterns = [#"(?i)(Q\d(?:_[A-Z0-9]+)+)"#, #"(?i)(BF16|F16|F32|FP16|FP32|INT8)"#]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let range = Range(match.range(at: 1), in: filename) else { continue }
        return String(filename[range]).uppercased()
    }
    return nil
}

private func executable(named name: String, extra: [String]) -> String? {
    (extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"])
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

private func capture(_ executable: URL, _ arguments: [String]) async -> (data: Data, status: Int32) {
    do {
        let result = try await CommandRunner.run(executable, arguments, timeout: CommandRunner.deadline(for: arguments))
        return (result.output, result.status)
    } catch { return (Data(error.localizedDescription.utf8), -1) }
}

private func run(_ executable: URL, _ arguments: [String]) async throws {
    let result = try await CommandRunner.run(executable, arguments, timeout: CommandRunner.deadline(for: arguments))
    guard result.status == 0 else { throw LocalModelClient.ModelError.failed(String(decoding: result.output, as: UTF8.self)) }
}

extension LocalModelClient {
    enum ModelError: LocalizedError {
        case runtimeUnavailable(String)
        case failed(String)
        var errorDescription: String? {
            switch self {
            case let .runtimeUnavailable(runtime): "\(runtime) is not available."
            case let .failed(message): message.isEmpty ? "The model update failed." : message
            }
        }
    }
}
