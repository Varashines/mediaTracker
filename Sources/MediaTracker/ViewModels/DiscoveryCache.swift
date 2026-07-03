import Foundation

@Observable @MainActor
class DiscoveryCache {
    var cachedNetworks: [DiscoveryNode] = []
    var cachedStudios: [DiscoveryNode] = []
    var cachedGenres: [DiscoveryNode] = []
    var cachedLanguages: [DiscoveryNode] = []
    var cachedBadges: [DiscoveryNode] = []
    var cachedProviders: [DiscoveryNode] = []
    var lastDiscoveryRefresh: Date?

    func purgeAll() {
        cachedNetworks = []
        cachedStudios = []
        cachedGenres = []
        cachedLanguages = []
        cachedBadges = []
        cachedProviders = []
        lastDiscoveryRefresh = nil
    }
}
