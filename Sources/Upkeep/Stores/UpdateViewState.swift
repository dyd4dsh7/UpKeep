import Foundation

@MainActor
final class UpdateViewState: ObservableObject {
    @Published var filter: UpdateListFilter = .all
    @Published var sortOrder: UpdateSortOrder = .recommended
    @Published var sortAscending = true
}
