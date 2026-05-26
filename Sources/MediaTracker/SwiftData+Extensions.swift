import SwiftData

extension Sequence where Element: PersistentModel {
    var liveModels: [Element] {
        filter { !$0.isDeleted && $0.modelContext != nil }
    }
}
