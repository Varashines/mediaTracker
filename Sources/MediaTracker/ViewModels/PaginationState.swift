import Foundation

@Observable @MainActor
class PaginationState {
    var totalItemCount: Int = 0
    var currentOffset: Int = 0
    let pageSize: Int = 50
    var isLoadingMore: Bool = false
    var isFastScrolling: Bool = false
}
