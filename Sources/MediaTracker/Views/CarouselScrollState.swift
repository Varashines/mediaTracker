import Foundation
import Observation
import SwiftUI

/// Shared, observation-backed scroll tracking for a single horizontal carousel.
///
/// `HomeCarouselSection` and friends hold this in `@State`. Progress and
/// fast-scroll flips are written by `ScrollingHStack` but only views that
/// *read* those fields re-evaluate (header / environment injector) — not the
/// card `ForEach`.
@Observable
@MainActor
final class CarouselScrollState {
    var progress: Double = 0
    var isFastScrolling: Bool = false
}

private struct FastScrollingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// True while a parent (vertical home) or the current horizontal carousel
    /// is in a fast-scroll gesture. Cards read this instead of taking a
    /// constructor flag so `Equatable` `==` can stay metadata-only.
    var isFastScrolling: Bool {
        get { self[FastScrollingKey.self] }
        set { self[FastScrollingKey.self] = newValue }
    }
}

/// Applies combined vertical + horizontal fast-scroll into the environment.
/// Reads vertical from the ambient env (set by `trackFastScrollingEnv`) so
/// parent screens never thread a `Bool` prop through the tree.
struct FastScrollingEnvironmentModifier: ViewModifier {
    @Environment(\.isFastScrolling) private var vertical: Bool
    var state: CarouselScrollState

    func body(content: Content) -> some View {
        content.environment(\.isFastScrolling, vertical || state.isFastScrolling)
    }
}

extension View {
    func fastScrollingEnvironment(state: CarouselScrollState) -> some View {
        modifier(FastScrollingEnvironmentModifier(state: state))
    }
}
