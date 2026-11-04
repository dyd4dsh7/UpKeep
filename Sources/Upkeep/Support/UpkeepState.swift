import SwiftUI

// macOS 27 SDKs expose both the State property wrapper and a same-named macro.
// The latter requires a SwiftUIMacros plugin absent from Command Line Tools.
// Select the public property wrapper explicitly, keeping native SwiftUI state
// storage and bindings on every supported SDK without requiring that plugin.
typealias UpkeepState<Value> = SwiftUI.State<Value>
