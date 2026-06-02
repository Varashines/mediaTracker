import Foundation

@Observable @MainActor
class DiscoveryCache {
    var cachedNetworks: [DiscoveryNode] = []
    var cachedGenres: [DiscoveryNode] = []
    var cachedLanguages: [DiscoveryNode] = []
    var cachedBadges: [DiscoveryNode] = []
    var lastDiscoveryRefresh: Date?

    func purgeAll() {
        cachedNetworks = []
        cachedGenres = []
        cachedLanguages = []
        cachedBadges = []
        lastDiscoveryRefresh = nil
    }
}
