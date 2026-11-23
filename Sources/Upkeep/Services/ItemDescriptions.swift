import Foundation

/// An item whose one-line "what is this" description has to be looked up.
/// Items Upkeep can describe without a lookup never become a request.
enum ItemDescriptionRequest: Hashable, Sendable {
    case developerPackage(manager: DeveloperPackageManager, identifier: String)
    case app(AppDescriptionInput)
    case model(runtime: LocalModelRuntime, repository: String)

    var key: String {
        switch self {
        case let .developerPackage(manager, identifier):
            "dev:\(manager.rawValue):\(identifier.lowercased())"
        case let .app(input):
            input.key
        case let .model(runtime, repository):
            "model:\(runtime.rawValue):\(repository.lowercased())"
        }
    }
}

struct AppDescriptionInput: Hashable, Sendable {
    let bundleIdentifier: String?
    let name: String
    let url: URL
    let isAppStore: Bool

    var key: String { "app:" + (bundleIdentifier?.lowercased() ?? url.path) }
}

enum ItemDescriptionLookup: Equatable, Sendable {
    case found(String)
    case notFound
}

protocol ItemDescribing: Sendable {
    /// Results keyed by `ItemDescriptionRequest.key`. A request missing from
    /// the result failed, for example offline, and can be retried later.
    func describe(_ requests: [ItemDescriptionRequest]) async -> [String: ItemDescriptionLookup]
}

// MARK: - Choosing a description or a lookup

enum ItemDescriptions {
    /// Descriptions are a single line of plain text; long store listings are cut
    /// to their first sentence.
    static let maximumLength = 160

    static func builtIn(for package: DeveloperPackage) -> String? {
        let name = package.name
        switch package.manager {
        case .node: return "JavaScript runtime built on Chrome’s V8 engine"
        case .bun: return "Fast JavaScript runtime, bundler, test runner and package manager"
        case .deno: return "Secure runtime for JavaScript and TypeScript"
        case .rustup: return "Rust compiler toolchain managed by rustup"
        case .nvm: return "Node Version Manager, for installing and switching Node.js versions"
        case .claudeCode: return "Anthropic’s agentic coding tool for the terminal"
        case .flutter: return "Google’s toolkit for building apps for mobile, web and desktop from one codebase"
        case .poetry: return "Python dependency management and packaging tool"
        case .xcodeSimulators: return "Simulator runtime for running and testing apps in Xcode"
        case .swiftly: return "Swift toolchain installed with swiftly"
        case .juliaup: return "Julia language release managed by juliaup"
        case .pyenv: return "Python version managed by pyenv"
        case .rbenv: return "Ruby version managed by rbenv"
        case .volta, .fnm, .mise, .asdf, .sdkman, .ghcup, .googleCloud:
            return knownTools[normalizedToolName(name)]
        case .uv where isPythonRuntime(package):
            return "Python interpreter installed by uv"
        case .go where knownTools[normalizedToolName(name)] != nil:
            return knownTools[normalizedToolName(name)]
        default:
            return nil
        }
    }

    static func request(for package: DeveloperPackage) -> ItemDescriptionRequest? {
        guard builtIn(for: package) == nil else { return nil }
        let identifier = (package.registryIdentifier ?? package.name).trimmingCharacters(in: .whitespaces)
        guard !identifier.isEmpty else { return nil }
        switch package.manager {
        case .npm, .pnpm, .yarn, .uv, .pipx, .python, .rubyGems, .cargo, .dart, .composer, .conda, .pixi:
            // Registry names never contain spaces; display names such as
            // "CPython Python 3.10" are not packages.
            guard !identifier.contains(where: \.isWhitespace) else { return nil }
        case .vsCode, .dockerImages:
            break
        case .githubCLI, .go:
            guard githubRepository(from: identifier) != nil else { return nil }
        default:
            return nil
        }
        return .developerPackage(manager: package.manager, identifier: identifier)
    }

    static func request(for app: InstalledApp) -> ItemDescriptionRequest? {
        guard builtIn(for: app) == nil else { return nil }
        return .app(AppDescriptionInput(
            bundleIdentifier: app.bundleIdentifier,
            name: app.name,
            url: app.url,
            isAppStore: app.updateManagement == .appStore || app.hasAppStoreReceipt
        ))
    }

    static func builtIn(for app: InstalledApp) -> String? {
        app.bundleIdentifier.flatMap { appleApps[$0.lowercased()] }
    }

    static func builtIn(for model: LocalLLMModel) -> String? {
        model.runtime == .ollama ? modelFamilyDescription(for: model.name) : nil
    }

    static func request(for model: LocalLLMModel) -> ItemDescriptionRequest? {
        guard model.runtime != .ollama else { return nil }
        let parts = model.name.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return .model(runtime: model.runtime, repository: parts.prefix(2).joined(separator: "/"))
    }

    static func isPythonRuntime(_ package: DeveloperPackage) -> Bool {
        let name = package.name.lowercased()
        return name.hasPrefix("cpython") || name.hasPrefix("pypy") || name.hasPrefix("graalpy")
            || package.installationContext?.localizedCaseInsensitiveContains("runtime") == true
    }

    /// "github.com/cli/cli/v2/cmd/gh" and "owner/gh-extension" name a repository.
    static func githubRepository(from identifier: String) -> String? {
        var parts = identifier.split(separator: "/").map(String.init)
        if parts.first?.lowercased() == "github.com" { parts.removeFirst() }
        else if identifier.contains(".") && parts.count > 2 { return nil }
        guard parts.count >= 2 else { return nil }
        let owner = parts[0], repo = parts[1]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard [owner, repo].allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return "\(owner)/\(repo)"
    }

    /// Turns registry or store text into one short, plain line.
    static func clean(_ raw: String?, name: String? = nil) -> String? {
        guard var text = raw else { return nil }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Registries wrap long lines, so only a blank line ends a paragraph.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if let firstParagraph = text.components(separatedBy: "\n\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            text = firstParagraph
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let name, text.caseInsensitiveCompare(name) == .orderedSame { return nil }
        if text.count > maximumLength, let sentenceEnd = firstSentenceEnd(in: text) {
            text = String(text[..<sentenceEnd])
        }
        if text.count > maximumLength {
            let cut = text.prefix(maximumLength - 1)
            let wordBoundary = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
            text = wordBoundary.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—")) + "…"
        }
        return text
    }

    private static func firstSentenceEnd(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if ".!?".contains(character), next == text.endIndex || text[next] == " " {
                return character == "." ? index : next
            }
            index = next
        }
        return nil
    }

    static func normalizedToolName(_ name: String) -> String {
        let base = name.split(whereSeparator: { $0 == "@" || $0 == " " }).first.map(String.init) ?? name
        return base.lowercased()
    }

    // MARK: Local AI models

    static func modelTaskDescription(pipelineTag: String?, baseModel: String?, author: String?, repository: String) -> String? {
        let task: String?
        switch pipelineTag {
        case "text-generation": task = "Text generation model"
        case "image-text-to-text", "visual-question-answering": task = "Vision language model"
        case "feature-extraction", "sentence-similarity": task = "Embedding model for search and retrieval"
        case "automatic-speech-recognition": task = "Speech recognition model"
        case "text-to-speech": task = "Text-to-speech model"
        case "text-to-image": task = "Image generation model"
        case "image-to-image": task = "Image editing model"
        case "translation": task = "Translation model"
        case "summarization": task = "Summarization model"
        case "fill-mask": task = "Masked language model"
        case "text-classification": task = "Text classification model"
        case "image-classification": task = "Image classification model"
        case "object-detection": task = "Object detection model"
        case let tag?:
            let words = tag.replacingOccurrences(of: "-", with: " ")
            task = words.prefix(1).uppercased() + words.dropFirst() + " model"
        case nil:
            task = modelFamilyDescription(for: repository)
        }
        guard let task else { return nil }
        if let baseModel, baseModel.caseInsensitiveCompare(repository) != .orderedSame {
            return "\(task) based on \(baseModel)"
        }
        if pipelineTag != nil, let author, !author.isEmpty { return "\(task) from \(author)" }
        return task
    }

    static func modelFamilyDescription(for name: String) -> String? {
        let lowered = name.lowercased()
        let model = lowered.split(separator: "/").last.map(String.init) ?? lowered
        if model.contains("embed") { return "Embedding model for search and retrieval" }
        let family = modelFamilies.first { model.hasPrefix($0.prefix) || model.contains("-\($0.prefix)") }
        guard let family else { return nil }
        if model.contains("coder") || model.hasPrefix("code") { return "\(family.name) model for writing code" }
        if model.range(of: "vl($|[-:_.])", options: .regularExpression) != nil
            || model.contains("vision") || model.contains("llava") {
            return "\(family.name) model that understands images"
        }
        return "\(family.name) language model"
    }

    private static let modelFamilies: [(prefix: String, name: String)] = [
        ("codellama", "Meta’s Code Llama"), ("llava", "LLaVA"), ("llama", "Meta’s Llama"),
        ("qwq", "Alibaba’s Qwen reasoning"), ("qwen", "Alibaba’s Qwen"),
        ("codegemma", "Google’s CodeGemma"), ("gemma", "Google’s Gemma"),
        ("mixtral", "Mistral AI’s Mixtral"), ("devstral", "Mistral AI’s Devstral coding"),
        ("magistral", "Mistral AI’s Magistral reasoning"), ("ministral", "Mistral AI’s Ministral"),
        ("mistral", "Mistral AI’s"), ("phi", "Microsoft’s Phi small"),
        ("deepseek", "DeepSeek’s"), ("gpt-oss", "OpenAI’s open-weight"),
        ("granite", "IBM’s Granite"), ("olmo", "Ai2’s OLMo"), ("smollm", "Hugging Face’s SmolLM small"),
        ("command-r", "Cohere’s Command R"), ("kimi", "Moonshot AI’s Kimi"), ("glm", "Zhipu AI’s GLM"),
        ("nemotron", "NVIDIA’s Nemotron"), ("falcon", "TII’s Falcon"), ("starcoder", "BigCode’s StarCoder"),
        ("tinyllama", "TinyLlama small"), ("gpt2", "OpenAI’s GPT-2")
    ]

    // MARK: Tables

    /// Runtimes and tools installed by version managers such as mise, asdf,
    /// SDKMAN!, GHCup and the Google Cloud CLI.
    static let knownTools: [String: String] = [
        "node": "JavaScript runtime built on Chrome’s V8 engine",
        "nodejs": "JavaScript runtime built on Chrome’s V8 engine",
        "node.js": "JavaScript runtime built on Chrome’s V8 engine",
        "npm": "Package manager for JavaScript",
        "pnpm": "Fast, disk-space-efficient JavaScript package manager",
        "yarn": "JavaScript package manager",
        "bun": "Fast JavaScript runtime, bundler, test runner and package manager",
        "deno": "Secure runtime for JavaScript and TypeScript",
        "python": "Python programming language",
        "ruby": "Ruby programming language",
        "go": "Go programming language toolchain",
        "golang": "Go programming language toolchain",
        "rust": "Rust programming language toolchain",
        "java": "Java Development Kit for building and running Java apps",
        "kotlin": "Kotlin programming language compiler",
        "scala": "Scala programming language",
        "groovy": "Groovy programming language for the JVM",
        "gradle": "Build automation tool for Java and Android projects",
        "maven": "Build and dependency tool for Java projects",
        "sbt": "Build tool for Scala and Java projects",
        "springboot": "Command-line tool for Spring Boot apps",
        "jbang": "Runs Java code as scripts",
        "visualvm": "Java profiling and monitoring tool",
        "erlang": "Erlang programming language and runtime",
        "elixir": "Elixir programming language",
        "php": "PHP programming language",
        "zig": "Zig programming language toolchain",
        "swift": "Swift programming language toolchain",
        "dotnet": ".NET SDK for building apps in C#, F# and Visual Basic",
        "terraform": "Infrastructure-as-code tool from HashiCorp",
        "kubectl": "Command-line tool for Kubernetes clusters",
        "helm": "Package manager for Kubernetes",
        "ghc": "Glasgow Haskell Compiler",
        "cabal": "Haskell build tool and package manager",
        "hls": "Haskell Language Server for editor support",
        "stack": "Haskell build tool",
        "gcloud": "Google Cloud command-line tool",
        "google cloud cli": "Command-line tools for Google Cloud",
        "google-cloud-sdk": "Command-line tools for Google Cloud",
        "gsutil": "Google Cloud Storage command-line tool",
        "bq": "BigQuery command-line tool",
        "core": "Core commands of the Google Cloud CLI",
        "gke-gcloud-auth-plugin": "Signs kubectl in to Google Kubernetes Engine",
        "cloud-sql-proxy": "Secure connections to Cloud SQL databases",
        "kustomize": "Customizes Kubernetes configuration files",
        "uv": "Fast Python package and project manager",
        "pipx": "Installs Python command-line apps in isolated environments",
        "poetry": "Python dependency management and packaging tool",
        "flutter": "Google’s toolkit for building apps for mobile, web and desktop",
        "dart": "Dart programming language SDK",
        "lua": "Lua scripting language",
        "perl": "Perl programming language",
        "r": "R language for statistics and data analysis",
        "julia": "Julia language for technical computing",
        "ocaml": "OCaml programming language",
        "postgres": "PostgreSQL database server",
        "postgresql": "PostgreSQL database server",
        "redis": "In-memory data store",
        "awscli": "Amazon Web Services command-line tool",
        "jq": "Command-line JSON processor",
        "gh": "GitHub’s official command-line tool",
        "act": "Runs GitHub Actions locally"
    ]

    /// Apps that come with macOS or from Apple, by bundle identifier.
    static let appleApps: [String: String] = [
        "com.apple.safari": "Apple’s web browser",
        "com.apple.mail": "Apple’s email app",
        "com.apple.ical": "Apple’s calendar app",
        "com.apple.addressbook": "Apple’s contacts app",
        "com.apple.mobilesms": "Apple’s app for iMessage and text messages",
        "com.apple.facetime": "Apple’s video and audio calling app",
        "com.apple.photos": "Apple’s photo library and editor",
        "com.apple.music": "Apple’s music player and Apple Music app",
        "com.apple.tv": "Apple’s app for Apple TV+ and your video library",
        "com.apple.podcasts": "Apple’s podcast app",
        "com.apple.books": "Apple’s ebook and audiobook app",
        "com.apple.ibooksx": "Apple’s ebook and audiobook app",
        "com.apple.news": "Apple’s news reader",
        "com.apple.stocks": "Apple’s stock market app",
        "com.apple.weather": "Apple’s weather app",
        "com.apple.maps": "Apple’s maps and directions app",
        "com.apple.notes": "Apple’s note-taking app",
        "com.apple.reminders": "Apple’s to-do list app",
        "com.apple.freeform": "Apple’s whiteboard app for brainstorming",
        "com.apple.journal": "Apple’s journaling app",
        "com.apple.passwords": "Apple’s password manager",
        "com.apple.preview": "Apple’s viewer for PDFs and images",
        "com.apple.textedit": "Apple’s simple text editor",
        "com.apple.calculator": "Apple’s calculator",
        "com.apple.dictionary": "Apple’s dictionary and thesaurus",
        "com.apple.finder": "macOS file manager",
        "com.apple.appstore": "Apple’s store for Mac apps",
        "com.apple.systempreferences": "Settings for your Mac",
        "com.apple.terminal": "Apple’s command-line terminal",
        "com.apple.activitymonitor": "Shows what is using your Mac’s processor, memory and energy",
        "com.apple.diskutility": "Manages disks and volumes",
        "com.apple.console": "Shows system logs and crash reports",
        "com.apple.keychainaccess": "Manages passwords, keys and certificates",
        "com.apple.screenshot.launcher": "Takes screenshots and screen recordings",
        "com.apple.quicktimeplayerx": "Apple’s video and audio player",
        "com.apple.voicememos": "Apple’s voice recorder",
        "com.apple.findmy": "Finds your Apple devices and friends",
        "com.apple.home": "Controls HomeKit accessories",
        "com.apple.shortcuts": "Apple’s app for automating tasks",
        "com.apple.automator": "Apple’s older automation tool",
        "com.apple.scripteditor2": "Writes and runs AppleScript",
        "com.apple.photobooth": "Takes photos and videos with your camera",
        "com.apple.chess": "Chess game",
        "com.apple.fontbook": "Installs and manages fonts",
        "com.apple.digitalcolormeter": "Measures colours on screen",
        "com.apple.grapher": "Graphs equations",
        "com.apple.imagecapture": "Imports photos from cameras and scanners",
        "com.apple.systeminformation": "Shows details about your Mac’s hardware and software",
        "com.apple.timemachine": "Restores files from Time Machine backups",
        "com.apple.backup.launcher": "Restores files from Time Machine backups",
        "com.apple.migrateassistant": "Moves data from another Mac or PC",
        "com.apple.bootcampassistant": "Installs Windows on Intel Macs",
        "com.apple.audio.audiomidisetup": "Configures audio and MIDI devices",
        "com.apple.bluetoothfileexchange": "Sends files over Bluetooth",
        "com.apple.colorsyncutility": "Manages colour profiles",
        "com.apple.voiceoverutility": "Configures the VoiceOver screen reader",
        "com.apple.iphonemirroring": "Uses your iPhone from your Mac",
        "com.apple.tips": "Tips for getting more out of your Mac",
        "com.apple.games": "Apple’s app for your games",
        "com.apple.dt.xcode": "Apple’s tools for building apps for Apple platforms",
        "com.apple.dt.instruments": "Profiles app performance",
        "com.apple.iwork.pages": "Apple’s word processor",
        "com.apple.iwork.numbers": "Apple’s spreadsheet app",
        "com.apple.iwork.keynote": "Apple’s presentation app",
        "com.apple.garageband10": "Apple’s music creation studio",
        "com.apple.imovieapp": "Apple’s video editor",
        "com.apple.finalcut": "Apple’s professional video editor",
        "com.apple.logic10": "Apple’s professional music production app",
        "com.apple.testflight": "Installs beta versions of apps",
        "com.apple.developer.app": "Apple’s app for developer news and videos",
        "com.apple.configurator": "Configures and deploys iPhone, iPad and Mac devices",
        "com.apple.remotedesktop": "Manages Macs on a network",
        "com.apple.clips": "Apple’s app for making short videos"
    ]

    /// LSApplicationCategoryType values such as `public.app-category.developer-tools`.
    static func categoryDescription(_ category: String?) -> String? {
        guard let category, category.hasPrefix("public.app-category.") else { return nil }
        let slug = String(category.dropFirst("public.app-category.".count))
        let label: String
        switch slug {
        case "developer-tools": label = "Developer tool"
        case "utilities": label = "Utility"
        case "productivity": label = "Productivity app"
        case "graphics-design": label = "Graphics and design app"
        case "social-networking": label = "Social networking app"
        case "healthcare-fitness": label = "Health and fitness app"
        case "photography": label = "Photography app"
        case "video": label = "Video app"
        case "music": label = "Music app"
        case "games": label = "Game"
        case let value where value.hasSuffix("-games"): label = "Game"
        default:
            let words = slug.replacingOccurrences(of: "-", with: " ")
            guard !words.isEmpty else { return nil }
            label = words.prefix(1).uppercased() + words.dropFirst() + " app"
        }
        return label
    }
}

/// Makes no network requests; used by the offline UI fixture.
struct OfflineItemDescriber: ItemDescribing {
    func describe(_ requests: [ItemDescriptionRequest]) async -> [String: ItemDescriptionLookup] { [:] }
}

// MARK: - Live lookups

actor ItemDescriptionClient: ItemDescribing {
    private let caskCatalog: @Sendable () async throws -> [CatalogCask]
    private let appStoreLookup: @Sendable ([String]) async throws -> [String: AppStoreClient.LookupResult]
    private let fetch: @Sendable (URLRequest) async -> FetchOutcome
    private var caskDescriptions: [String: String]?

    enum FetchOutcome: Sendable {
        case data(Data)
        case notFound
        case failed
    }

    init(
        caskCatalog: @escaping @Sendable () async throws -> [CatalogCask] = { try await HomebrewClient().caskCatalog() },
        appStoreLookup: @escaping @Sendable ([String]) async throws -> [String: AppStoreClient.LookupResult] = {
            try await AppStoreClient().lookup(bundleIDs: $0)
        },
        fetch: @escaping @Sendable (URLRequest) async -> FetchOutcome = ItemDescriptionClient.liveFetch
    ) {
        self.caskCatalog = caskCatalog
        self.appStoreLookup = appStoreLookup
        self.fetch = fetch
    }

    static let maximumConcurrentRequests = 6

    func describe(_ requests: [ItemDescriptionRequest]) async -> [String: ItemDescriptionLookup] {
        var results: [String: ItemDescriptionLookup] = [:]
        var apps: [AppDescriptionInput] = []
        var others: [ItemDescriptionRequest] = []
        for request in Set(requests) {
            if case let .app(input) = request { apps.append(input) } else { others.append(request) }
        }
        if !apps.isEmpty { results.merge(await describeApps(apps)) { first, _ in first } }

        let fetch = self.fetch
        for start in stride(from: 0, to: others.count, by: Self.maximumConcurrentRequests) {
            let slice = others[start..<min(start + Self.maximumConcurrentRequests, others.count)]
            await withTaskGroup(of: (String, ItemDescriptionLookup?).self) { group in
                for request in slice {
                    group.addTask { (request.key, await Self.lookup(request, fetch: fetch)) }
                }
                for await (key, lookup) in group {
                    if let lookup { results[key] = lookup }
                }
            }
        }
        return results
    }

    // MARK: Apps

    private func describeApps(_ apps: [AppDescriptionInput]) async -> [String: ItemDescriptionLookup] {
        var results: [String: ItemDescriptionLookup] = [:]
        let storeIDs = apps.filter(\.isAppStore).compactMap(\.bundleIdentifier)
        var storeListings: [String: AppStoreClient.LookupResult] = [:]
        var storeFailed = false
        for start in stride(from: 0, to: storeIDs.count, by: AppStoreClient.lookupBatchSize) {
            let chunk = Array(storeIDs[start..<min(start + AppStoreClient.lookupBatchSize, storeIDs.count)])
            do { storeListings.merge(try await appStoreLookup(chunk)) { first, _ in first } }
            catch { storeFailed = true }
        }
        let casks = await caskDescriptionIndex()
        for app in apps {
            if let bundleID = app.bundleIdentifier,
               let text = ItemDescriptions.clean(storeListings[AppStoreClient.lookupKey(bundleID)]?.description, name: app.name) {
                results[app.key] = .found(text)
            } else if let text = casks?[catalogKey(app.name)] {
                results[app.key] = .found(text)
            } else if let text = ItemDescriptions.categoryDescription(Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String) {
                results[app.key] = .found(text)
            } else if (app.isAppStore && storeFailed) || casks == nil {
                // Try again when the store or catalog is reachable.
                continue
            } else {
                results[app.key] = .notFound
            }
        }
        return results
    }

    private func caskDescriptionIndex() async -> [String: String]? {
        if let caskDescriptions { return caskDescriptions }
        guard let catalog = try? await caskCatalog() else { return nil }
        let index = Self.caskDescriptionIndex(catalog)
        caskDescriptions = index
        return index
    }

    /// Matches apps to casks the same way Adoptable does: by cask name, app
    /// bundle name and token, keeping the first match.
    static func caskDescriptionIndex(_ catalog: [CatalogCask]) -> [String: String] {
        var index: [String: String] = [:]
        for cask in catalog {
            guard let text = ItemDescriptions.clean(cask.desc) else { continue }
            let names = cask.name + cask.artifactAppNames.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
            } + [cask.token]
            for name in names {
                let key = catalogKey(name)
                if !key.isEmpty, index[key] == nil { index[key] = text }
            }
        }
        return index
    }

    // MARK: Registries

    private static func lookup(_ request: ItemDescriptionRequest, fetch: @Sendable (URLRequest) async -> FetchOutcome) async -> ItemDescriptionLookup? {
        switch request {
        case let .developerPackage(manager, identifier):
            return await lookupPackage(manager: manager, identifier: identifier, fetch: fetch)
        case let .model(_, repository):
            guard let url = URL(string: "https://huggingface.co/api/models/\(pathEncoded(repository))") else { return .notFound }
            return await json(url, fetch: fetch) { object in
                let card = object["cardData"] as? [String: Any]
                let base = (card?["base_model"] as? String) ?? (card?["base_model"] as? [String])?.first
                return ItemDescriptions.modelTaskDescription(
                    pipelineTag: object["pipeline_tag"] as? String,
                    baseModel: base,
                    author: object["author"] as? String,
                    repository: repository
                )
            }
        case .app:
            return nil
        }
    }

    private static func lookupPackage(
        manager: DeveloperPackageManager,
        identifier: String,
        fetch: @Sendable (URLRequest) async -> FetchOutcome
    ) async -> ItemDescriptionLookup? {
        let encoded = pathEncoded(identifier)
        switch manager {
        case .npm, .pnpm, .yarn:
            return await json(URL(string: "https://registry.npmjs.org/\(encoded)/latest"), fetch: fetch) { $0["description"] as? String }
        case .uv, .pipx, .python:
            return await json(URL(string: "https://pypi.org/pypi/\(encoded)/json"), fetch: fetch) {
                ($0["info"] as? [String: Any])?["summary"] as? String
            }
        case .rubyGems:
            return await json(URL(string: "https://rubygems.org/api/v1/gems/\(encoded).json"), fetch: fetch) { $0["info"] as? String }
        case .cargo:
            return await json(URL(string: "https://crates.io/api/v1/crates/\(encoded)"), fetch: fetch) {
                ($0["crate"] as? [String: Any])?["description"] as? String
            }
        case .dart:
            return await json(URL(string: "https://pub.dev/api/packages/\(encoded)"), fetch: fetch) {
                (($0["latest"] as? [String: Any])?["pubspec"] as? [String: Any])?["description"] as? String
            }
        case .composer:
            return await json(URL(string: "https://repo.packagist.org/p2/\(identifier.lowercased()).json"), fetch: fetch) {
                (($0["packages"] as? [String: Any])?[identifier.lowercased()] as? [[String: Any]])?.first?["description"] as? String
            }
        case .conda, .pixi:
            let name = identifier.split(separator: "/").last.map(String.init) ?? identifier
            return await json(URL(string: "https://api.anaconda.org/package/conda-forge/\(pathEncoded(name))"), fetch: fetch) {
                $0["summary"] as? String
            }
        case .githubCLI, .go:
            guard let repository = ItemDescriptions.githubRepository(from: identifier) else { return .notFound }
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            return await json(request, fetch: fetch) { $0["description"] as? String }
        case .dockerImages:
            guard let repository = dockerHubRepository(identifier) else { return .notFound }
            return await json(URL(string: "https://hub.docker.com/v2/repositories/\(repository)/"), fetch: fetch) {
                $0["description"] as? String
            }
        case .vsCode:
            return await visualStudioMarketplaceDescription(extensionID: identifier, fetch: fetch)
        default:
            return .notFound
        }
    }

    /// "postgres:17-alpine" → "library/postgres"; images from other registries
    /// such as ghcr.io have no Docker Hub page.
    static func dockerHubRepository(_ reference: String) -> String? {
        var name = reference
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        var parts = name.split(separator: "/").map(String.init)
        if let first = parts.first, parts.count > 1, first.contains(".") || first.contains(":") || first == "localhost" {
            guard first == "docker.io" || first == "registry-1.docker.io" else { return nil }
            parts.removeFirst()
        }
        guard var last = parts.popLast() else { return nil }
        if let colon = last.firstIndex(of: ":") { last = String(last[..<colon]) }
        parts.append(last)
        if parts.count == 1 { parts.insert("library", at: 0) }
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts.joined(separator: "/").lowercased()
    }

    private static func visualStudioMarketplaceDescription(
        extensionID: String,
        fetch: @Sendable (URLRequest) async -> FetchOutcome
    ) async -> ItemDescriptionLookup? {
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "filters": [["criteria": [["filterType": 7, "value": extensionID]]]],
            "flags": 0
        ]) else { return nil }
        var request = URLRequest(url: EditorExtensionGallery.visualStudioMarketplace.queryURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json;api-version=7.2-preview.1", forHTTPHeaderField: "Accept")
        return await json(request, fetch: fetch) { object in
            let extensions = (object["results"] as? [[String: Any]])?.first?["extensions"] as? [[String: Any]]
            return extensions?.first?["shortDescription"] as? String
        }
    }

    private static func json(
        _ url: URL?,
        fetch: @Sendable (URLRequest) async -> FetchOutcome,
        extract: ([String: Any]) -> String?
    ) async -> ItemDescriptionLookup? {
        guard let url else { return .notFound }
        return await json(URLRequest(url: url), fetch: fetch, extract: extract)
    }

    private static func json(
        _ request: URLRequest,
        fetch: @Sendable (URLRequest) async -> FetchOutcome,
        extract: ([String: Any]) -> String?
    ) async -> ItemDescriptionLookup? {
        switch await fetch(request) {
        case .failed: return nil
        case .notFound: return .notFound
        case let .data(data):
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return ItemDescriptions.clean(extract(object)).map(ItemDescriptionLookup.found) ?? .notFound
        }
    }

    @Sendable static func liveFetch(_ request: URLRequest) async -> FetchOutcome {
        var request = request
        request.timeoutInterval = 15
        request.setValue("Upkeep/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await PublisherHTTPClient.data(for: request, maximumBytes: 8 * 1_024 * 1_024) else {
            return .failed
        }
        switch response.statusCode {
        case 200..<300: return .data(data)
        case 404, 410: return .notFound
        default: return .failed
        }
    }

    private static func pathEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private func catalogKey(_ value: String) -> String { value.lowercased().filter(\.isLetter) }

// MARK: - Cache

/// Descriptions rarely change, so they are kept on disk: found ones for 30
/// days, and "nothing found" for 7 days so missing items are not re-requested
/// on every launch.
struct ItemDescriptionCache: Codable, Sendable {
    static let foundLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let notFoundLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let currentFormat = 1

    struct Entry: Codable, Sendable, Equatable {
        let text: String?
        let checkedAt: Date
    }

    var format = currentFormat
    var entries: [String: Entry] = [:]

    static var defaultURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upkeep", isDirectory: true)
            .appendingPathComponent("item-descriptions.json")
    }

    func isFresh(_ key: String, now: Date = Date()) -> Bool {
        guard let entry = entries[key] else { return false }
        let lifetime = entry.text == nil ? Self.notFoundLifetime : Self.foundLifetime
        return now.timeIntervalSince(entry.checkedAt) < lifetime
    }

    static func load(from url: URL?) -> ItemDescriptionCache {
        guard let url, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ItemDescriptionCache.self, from: data),
              cache.format == currentFormat else { return ItemDescriptionCache() }
        return cache
    }

    func save(to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
