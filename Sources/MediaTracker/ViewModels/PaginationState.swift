import Foundation

@Observable @MainActor
class PaginationState {
    var totalItemCount: Int = 0
    var currentOffset: Int = 0
    let pageSize: Int = 50
    var isLoadingMore: Bool = false
    var isFastScrolling: Bool = false
    /// True while the initial fetch for the current category is in flight —
    /// gates the main grid so it shows a skeleton instead of flashing the
    /// empty state on first load / category switches.
    var isInitialLoad: Bool = false
}
