import SwiftUI

enum UpkeepMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let standard = Animation.spring(duration: 0.32, bounce: 0.08)

    static var stateTransition: AnyTransition {
        // Scaling a surface also scales native AppKit progress controls through
        // fractional sizes, producing invalid min/max geometry during scans.
        .opacity
    }

    static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.985))
        )
    }
}

private struct UpkeepAnimatedModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    let animation: Animation

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeOut(duration: 0.1) : animation, value: value)
    }
}

private struct UpkeepTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

extension View {
    func upkeepAnimated<Value: Equatable>(
        for value: Value,
        animation: Animation = UpkeepMotion.standard
    ) -> some View {
        modifier(UpkeepAnimatedModifier(value: value, animation: animation))
    }

    func upkeepStateTransition() -> some View {
        modifier(UpkeepTransitionModifier(transition: UpkeepMotion.stateTransition))
    }

    func upkeepRowTransition() -> some View {
        modifier(UpkeepTransitionModifier(transition: UpkeepMotion.rowTransition))
    }
}
