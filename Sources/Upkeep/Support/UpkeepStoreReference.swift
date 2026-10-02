import SwiftUI

private struct UpkeepStoreReferenceKey: EnvironmentKey {
    static let defaultValue: UpkeepStore? = nil
}

extension EnvironmentValues {
    var upkeepStoreReference: UpkeepStore? {
        get { self[UpkeepStoreReferenceKey.self] }
        set { self[UpkeepStoreReferenceKey.self] = newValue }
    }
}

/// Supplies actions without subscribing to the root's broad Combine publisher.
/// Feature values read by the body use Observation; settings retain their legacy
/// subscription until AppSettings itself has a property-level observation model.
@MainActor
@propertyWrapper
struct UpkeepStoreReference: DynamicProperty {
    @Environment(\.upkeepStoreReference) private var reference
    @EnvironmentObject private var settings: AppSettings

    var wrappedValue: UpkeepStore {
        _ = settings
        guard let reference else { preconditionFailure("Missing Upkeep store reference in this scene") }
        return reference
    }

    // Use SwiftUI's native binding projection. This temporary wrapper is not a
    // stored DynamicProperty, so it does not install root observation in the view.
    var projectedValue: ObservedObject<UpkeepStore>.Wrapper {
        ObservedObject(wrappedValue: wrappedValue).projectedValue
    }
}
