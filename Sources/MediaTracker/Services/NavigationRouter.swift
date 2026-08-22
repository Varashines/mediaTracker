import SwiftUI

@Observable @MainActor
final class NavigationRouter {
    static let shared = NavigationRouter()
    var pendingSpotlightItemID: String?
    /// Request a sidebar category switch from anywhere (e.g. empty-state CTAs);
    /// consumed by ContentView like pendingSpotlightItemID.
    var pendingCategory: NavigationCategory?
}
