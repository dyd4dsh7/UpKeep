import Foundation

enum ListSorting {
    static func compareDates(
        _ left: Date?,
        _ right: Date?,
        leftName: String,
        rightName: String
    ) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?) where left != right:
            left < right ? .orderedAscending : .orderedDescending
        case (nil, .some):
            .orderedAscending
        case (.some, nil):
            .orderedDescending
        default:
            leftName.localizedStandardCompare(rightName)
        }
    }
}
