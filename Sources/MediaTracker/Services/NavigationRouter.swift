import SwiftUI

@Observable @MainActor
final class NavigationRouter {
    static let shared = NavigationRouter()
    var pendingSpotlightItemID: String?
}
