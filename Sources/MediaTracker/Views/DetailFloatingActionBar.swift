import SwiftUI

struct DetailFloatingActionBar: View {
    var viewModel: DetailViewModel
    var onAddToCollection: () -> Void
    var onRefresh: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onAddToCollection()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(.ultraThinMaterial))
            .clipShape(.capsule)
            .frame(width: 32, height: 32)
            .help("Add to Collection")

            Button {
                onRefresh()
            } label: {
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(.ultraThinMaterial))
            .clipShape(.capsule)
            .frame(width: 32, height: 32)
            .disabled(viewModel.isRefreshing)
            .help("Refresh")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Capsule().fill(.ultraThinMaterial))
            .clipShape(.capsule)
            .frame(width: 32, height: 32)
            .help("Remove")
        }
        .padding(4)
    }
}
