import SwiftUI
import SwiftData

struct WatchedThisWeek: View {
    @Environment(\.modelContext) private var modelContext
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var scrollProgress: Double = 0
    private let scrollSpace = "WTW_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Watched This Week",
                icon: "clock.fill",
                iconColor: .green,
                scrollProgress: scrollProgress
            )

            if isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: AppTheme.Spacing.large) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.2))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                }
                                .frame(width: 160, height: 240)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium - 1)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else if items.isEmpty {
                HStack {
                    Text("Nothing watched this week")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppTheme.Spacing.small)
            } else {
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress) {
                    ForEach(items, id: \.persistentModelID) { item in
                        NavigationLink(value: item) {
                            MediaThumbnailView(
                                item: item,
                                mode: .grid,
                                showTypeBadge: true,
                                isFastScrolling: false
                            )
                            .frame(width: 160)
                        }
                        .buttonStyle(.interactive)
                    }
                }
            }
        }
        .compositingGroup()
        .task { fetchRecentItems() }
    }

    private func fetchRecentItems() {
        let cutoff = Date(timeIntervalSinceNow: -7 * 86400)
        let predicate = #Predicate<MediaItem> {
            ($0.lastInteractionDate ?? cutoff) >= cutoff && $0.stateValue != "Wishlist"
        }
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        descriptor.fetchLimit = 20
        descriptor.sortBy = [SortDescriptor(\.lastInteractionDate, order: .reverse)]

        items = (try? modelContext.fetch(descriptor)) ?? []
        withAnimation(.easeInOut(duration: 0.25)) { isLoading = false }
    }
}
