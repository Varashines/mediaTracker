import SwiftUI

struct TrendingCarousel: View {
    let items: [MediaSearchResult]
    let title: String
    let onSelect: (MediaSearchResult) -> Void

    @State private var scrollProgress: Double = 0
    private let scrollSpace: String

    init(items: [MediaSearchResult], title: String, onSelect: @escaping (MediaSearchResult) -> Void) {
        self.items = items
        self.title = title
        self.onSelect = onSelect
        self.scrollSpace = "Trending_\(title.replacingOccurrences(of: " ", with: "_"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(title: title, icon: "flame.fill", iconColor: .red, scrollProgress: scrollProgress)

            if items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 160, height: 240)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                }
            } else {
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress) {
                    ForEach(items) { item in
                        TrendingPosterCard(item: item)
                            .onTapGesture { onSelect(item) }
                    }
                }
            }
        }
        .compositingGroup()
    }
}
