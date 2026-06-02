import Foundation

@Observable @MainActor
class CollectionState {
    var selectedCollectionID: UUID? = nil {
        didSet {
            if selectedCollectionID == nil {
                selectedCollectionName = nil
            }
        }
    }
    var selectedCollectionName: String? = nil
    var showingNoteOverlay: Bool = false
    var currentCollectionNote: String = ""
}
