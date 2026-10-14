import Foundation

/// A preview of the loaded dependency graph, not a prediction of brew's transaction.
struct HomebrewImpact: Sendable {
    let relatedServices: [HomebrewService]
    let unresolvedServiceNames: [String]
    let dependencies: [HomebrewPackage]
    let outdatedDependencies: [HomebrewPackage]
    let dependents: [HomebrewPackage]
    let unresolvedDependencies: [String]

    init(package: HomebrewPackage, inventory: [HomebrewPackage], services: [HomebrewService] = []) {
        let formulae = inventory.filter { $0.kind == .formula }
        let exact = Dictionary(formulae.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        let short = Dictionary(grouping: formulae) { $0.token.split(separator: "/").last.map(String.init) ?? $0.token }
        func resolve(_ token: String) -> HomebrewPackage? {
            if let value = exact[token] { return value }
            guard !token.contains("/"), let matches = short[token], matches.count == 1 else { return nil }
            return matches.first
        }
        var visited = Set([package.id])
        var queue = package.dependencies
        var cursor = 0
        var found: [HomebrewPackage] = []
        var missing = Set<String>()
        while cursor < queue.count {
            let token = queue[cursor]
            cursor += 1
            guard let dependency = resolve(token) else { missing.insert(token); continue }
            guard visited.insert(dependency.id).inserted else { continue }
            found.append(dependency)
            queue.append(contentsOf: dependency.dependencies)
        }
        var reverse: [String: [HomebrewPackage]] = [:]
        for candidate in inventory {
            for token in candidate.dependencies {
                if let dependency = resolve(token) { reverse[dependency.id, default: []].append(candidate) }
            }
        }
        var reverseSeen = Set([package.id])
        var reverseQueue = reverse[package.id] ?? []
        var affected: [HomebrewPackage] = []
        cursor = 0
        while cursor < reverseQueue.count {
            let candidate = reverseQueue[cursor]
            cursor += 1
            guard reverseSeen.insert(candidate.id).inserted else { continue }
            affected.append(candidate)
            reverseQueue.append(contentsOf: reverse[candidate.id] ?? [])
        }
        func order(_ left: HomebrewPackage, _ right: HomebrewPackage) -> Bool {
            if left.displayName != right.displayName { return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending }
            return left.id < right.id
        }
        dependencies = found.sorted(by: order)
        outdatedDependencies = dependencies.filter(\.isOutdated)
        dependents = affected.sorted(by: order)
        unresolvedDependencies = missing.sorted()
        var relevantIDs = Set(([package] + found.filter(\.isOutdated))
            .filter { $0.kind == .formula }.map(\.id))
        var serviceQueue = Array(relevantIDs)
        cursor = 0
        while cursor < serviceQueue.count {
            let id = serviceQueue[cursor]
            cursor += 1
            for dependent in reverse[id] ?? [] where dependent.kind == .formula {
                if relevantIDs.insert(dependent.id).inserted { serviceQueue.append(dependent.id) }
            }
        }
        relatedServices = services.filter { service in
            guard let formula = resolve(service.name) else { return false }
            return relevantIDs.contains(formula.id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        unresolvedServiceNames = Array(Set(services.filter { resolve($0.name) == nil }.map(\.name))).sorted()
    }
}
