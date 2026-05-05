import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
class NetworkThemeManager {
    static let shared = NetworkThemeManager()
    var themeMap: [String: String] = [:]
    private var modelContainer: ModelContainer?
    
    private init() {
        // Load legacy if exists, then migrate
        if let data = UserDefaults.standard.data(forKey: "cached_network_themes"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.themeMap = decoded
        }
    }

    func setup(with container: ModelContainer) {
        self.modelContainer = container
        syncWithDatabase()
    }
    
    func color(for network: String) -> Color? {
        guard let hex = themeMap[network] else { return nil }
        return Color(hex: hex)
    }
    
    func save(color: Color, for network: String) {
        let hex = color.toHex()
        themeMap[network] = hex
        
        // Persist to NetworkEntity if possible
        if let container = modelContainer {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate { $0.name == network })
            if let entity = try? context.fetch(descriptor).first {
                entity.themeColorHex = hex
                try? context.save()
            }
        }
    }
    
    func resetAll() {
        themeMap.removeAll()
        UserDefaults.standard.removeObject(forKey: "cached_network_themes")
        
        if let container = modelContainer {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<NetworkEntity>()
            if let entities = try? context.fetch(descriptor) {
                for entity in entities {
                    entity.themeColorHex = nil
                }
                try? context.save()
            }
        }
    }
    
    private func syncWithDatabase() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<NetworkEntity>()
        
        if let entities = try? context.fetch(descriptor) {
            for entity in entities {
                if let hex = entity.themeColorHex {
                    themeMap[entity.name] = hex
                }
            }
            
            // Migration: If we have items in themeMap that aren't in entities, try to update them
            // or if we have items in entities that aren't in themeMap, update themeMap.
            // The loop above already updated themeMap from entities.
            
            // Check if we need to migrate FROM themeMap TO entities (one-time)
            for (name, hex) in themeMap {
                if let entity = entities.first(where: { $0.name == name }), entity.themeColorHex == nil {
                    entity.themeColorHex = hex
                }
            }
            try? context.save()
            
            // Once migrated, clear legacy
            UserDefaults.standard.removeObject(forKey: "cached_network_themes")
        }
    }
}
