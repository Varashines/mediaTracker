import SwiftData
import SwiftUI

struct ContinueWatchingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    var onDiscoverySpotlight: (() -> Void)?

    @State private var scrollProgress: Double = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private let scrollSpace = "CW_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Continue Watching",
                icon: "play.fill",
                iconColor: .blue,
                scrollProgress: items.count > 1 ? scrollProgress : nil
            )

            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ForEach(items) { metadata in
                            Button {
                                onSelect(metadata)
                            } label: {
                                MediaThumbnailView(
                                    metadata: metadata, mode: .hero, namespace: namespace,
                                    isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.interactive)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium - 1)
                    .background(
                        GeometryReader { (geo: GeometryProxy) in
                            let minX: CGFloat = geo.frame(in: .named(scrollSpace)).minX
                            Color.clear
                                .preference(key: ScrollOffsetKey.self, value: [scrollSpace: minX])
                                .onAppear { contentWidth = geo.size.width }
                                .onChange(of: geo.size.width) { (_: CGFloat, newValue: CGFloat) in
                                    contentWidth = newValue
                                }
                        }
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: scrollSpace)
                .background(
                    GeometryReader { (geo: GeometryProxy) in
                        Color.clear
                            .onAppear { containerWidth = geo.size.width }
                            .onChange(of: geo.size.width) { (_: CGFloat, newValue: CGFloat) in containerWidth = newValue
                            }
                    }
                )
                .onPreferenceChange(ScrollOffsetKey.self) { (dict: [String: CGFloat]) in
                    guard let minX = dict[scrollSpace] else { return }
                    let maxScroll: CGFloat = max(1, contentWidth - containerWidth)
                    let currentScroll: CGFloat = max(0, -minX)
                    scrollProgress = min(1.0, Double(currentScroll / maxScroll))
                }
                .scrollClipDisabled()
                .onAppear { prewarm(items: items) }
                .onChange(of: items) { _, newItems in prewarm(items: newItems) }
            } else {
                // Discovery Spotlight Empty State
                Button {
                    onDiscoverySpotlight?()
                } label: {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(AppTheme.Font.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 54, height: 54)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text("Ready to start watching?")
                                .font(AppTheme.Font.title3)
                                .foregroundStyle(.primary)
                            Text("Explore the Discovery Hub to find your next favorite show.")
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(AppTheme.Spacing.medium)
                    .background {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .fill(.thinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.medium - 1)
            }
        }
        .compositingGroup()
    }

    private func prewarm(items: [MediaThumbnailMetadata]) {
        let urls = items.prefix(10).compactMap { $0.posterURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ImageCache.shared.prewarmImages(urls: urls, targetSize: .thumbMedium, priority: .normal)
        }
    }
}
