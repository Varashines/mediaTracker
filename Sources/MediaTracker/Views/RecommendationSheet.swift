import SwiftUI

struct RecommendationSheet: View {
    let filterName: String
    let filterType: FilterType
    let recommendations: [MooreMetricsRecommendation]
    let onDismiss: () -> Void
    var onSearch: ((String) -> Void)? = nil
    var debugTraits: [String] = []

    @Environment(\.colorScheme) var colorScheme
    @State private var addedIDs: Set<String> = []

    private var themeColor: Color {
        AppTheme.Colors.accent
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    cardsSection
                }
                .padding(AppTheme.Spacing.pageMargin)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("Recommended for You")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .frame(minWidth: 780, maxWidth: 820, minHeight: 500, maxHeight: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Based on your \(filterName) picks")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Text("\(recommendations.count) shows matched your taste")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)

                if !debugTraits.isEmpty {
                    Text("·")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.tertiary)
                    Text("Top traits: \(debugTraits.joined(separator: ", "))")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.Colors.accent)
                }
            }
        }
    }

    private var cardsSection: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
            spacing: 14
        ) {
            ForEach(recommendations) { rec in
                RecommendationCard(rec: rec, themeColor: themeColor) {
                    onSearch?(rec.name)
                    onDismiss()
                }
            }
        }
    }
}
