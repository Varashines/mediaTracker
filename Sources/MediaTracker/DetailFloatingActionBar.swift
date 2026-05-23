import SwiftUI

struct DetailFloatingActionBar: View {
    var viewModel: DetailViewModel
    var onAddToCollection: () -> Void
    var onRefresh: () -> Void
    var onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Button {
                onAddToCollection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                    Text("Collection")
                }
                .font(AppTheme.Font.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add to Collection")

            Divider()
                .frame(height: 14)

            Button {
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .font(AppTheme.Font.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)

            Divider()
                .frame(height: 14)

            Button(role: .destructive) {
                onDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Remove")
                }
                .font(AppTheme.Font.caption)
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.vertical, AppTheme.Spacing.small)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, y: 5)
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}
