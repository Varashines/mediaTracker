import Foundation

@Observable @MainActor
class CollectionState {
    var selectedCollectionID: UUID? = nil {
        didSet {
            if selectedCollectionID == nil {
                selectedCollectionName = nil
                isSmartCollection = false
                showingNoteOverlay = false
            }
        }
    }
    var selectedCollectionName: String? = nil
    /// Cached at selection time (see ContentView) so the toolbar never runs a
    /// database fetch per render just to disable smart-collection actions.
    var isSmartCollection: Bool = false
    var showingNoteOverlay: Bool = false
    var currentCollectionNote: String = ""
}
