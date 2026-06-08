import SwiftUI
import SwiftData

struct SmartBadgeView: View {
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    let hideEpisodeProgress: Bool
    
    @Environment(\.colorScheme) var colorScheme

    private static let badgeColors: [SmartBadge: (bg: Color, fg: Color)] = [
        .premiere: (Color.fromOKLCH(l: 0.6, c: 0.22, h: 310), Color.white),
        .finale: (Color.fromOKLCH(l: 0.62, c: 0.24, h: 340), Color.white),
        .bingeDrop: (Color.fromOKLCH(l: 0.7, c: 0.15, h: 190), Color.white),
        .new: (Color.fromOKLCH(l: 0.75, c: 0.18, h: 150), Color.white),
        .soon: (Color.fromOKLCH(l: 0.7, c: 0.2, h: 45), Color.white),
        .behind: (Color.fromOKLCH(l: 0.55, c: 0.12, h: 240), Color.white),
        .binge: (Color.fromOKLCH(l: 0.6, c: 0.28, h: 25), Color.white),
    ]



    init(item: MediaItem, hideEpisodeProgress: Bool = false) {
        self.item = item
        self.metadata = nil
        self.result = nil
        self.hideEpisodeProgress = hideEpisodeProgress
    }
    
    init(metadata: MediaThumbnailMetadata, hideEpisodeProgress: Bool = false) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
        self.hideEpisodeProgress = hideEpisodeProgress
    }

    init(result: MediaSearchResult, hideEpisodeProgress: Bool = false) {
        self.item = nil
        self.metadata = nil
        self.result = result
        self.hideEpisodeProgress = hideEpisodeProgress
    }

    var body: some View {
        if let metadata = metadata {
            if let label = metadata.smartBadgeLabel {
                intelligentBadge(label: label, isSparkle: metadata.isSparkleBadge, remaining: metadata.remainingCount, progress: metadata.progress)
            } else {
                statusUI(
                    isUpcoming: metadata.isUpcoming,
                    state: metadata.state,
                    badgeText: metadata.badgeText,
                    watchProgressLabel: metadata.watchProgress,
                    nextEpisodeLabel: metadata.nextEpisodeToWatchLabel,
                    progress: metadata.progress
                )
            }
        } else if let item = item, item.modelContext != nil {
            if let label = item.storedSmartBadgeLabel {
                intelligentBadge(label: label, isSparkle: item.storedSmartBadgeIsSparkle, remaining: item.remainingEpisodesCount, progress: item.storedProgress)
            } else {
                statusUI(
                    isUpcoming: item.storedIsUpcoming,
                    state: item.state,
                    badgeText: item.gridBadgeText,
                    watchProgressLabel: item.storedWatchProgressLabel,
                    nextEpisodeLabel: item.storedNextEpisodeLabel,
                    progress: item.storedProgress
                )
            }
        } else if let res = result, res.type == .movie {
             EmptyView()
        }
    }

    @ViewBuilder
    private func intelligentBadge(label: String, isSparkle: Bool, remaining: Int? = nil, progress: Double? = nil) -> some View {
        let badgeLabel = SmartBadge(rawValue: label)
        let badgeConfig: (bg: Color, fg: Color) = {
            if let label = badgeLabel, let config = Self.badgeColors[label] {
                return config
            }
            return (Color.secondary.opacity(0.8), Color.white)
        }()

        StatusBadgePrimitive(
            label: label,
            accentColor: badgeConfig.bg,
            isSolid: true,
            progress: progress,
            foregroundColor: badgeConfig.fg
        )
        .shadow(color: isSparkle ? badgeConfig.bg.opacity(0.3) : AppTheme.Colors.shadowAmbient(for: colorScheme), radius: isSparkle ? 6 : 3, y: 2)
    }

    @ViewBuilder
    private func statusUI(
        isUpcoming: Bool,
        state: MediaState?,
        badgeText: String?,
        watchProgressLabel: String?,
        nextEpisodeLabel: String?,
        progress: Double?
    ) -> some View {
        let currentState = state ?? .wishlist

        // Display Label (Used for accessibility, hidden in compact UI)
        let displayLabel = currentState.displayName

        // Progress Logic
        let isInProgress = (currentState == .active || currentState == .rewatching)
        let showProgressBar = !hideEpisodeProgress && !isUpcoming && isInProgress

        let finalAccent = currentState.accentColor
        let isSolid = true

        if currentState == .completed {
            EmptyView()
        } else {
            StatusBadgePrimitive(
                label: displayLabel,
                accentColor: finalAccent,
                isSolid: isSolid,
                progress: showProgressBar ? progress : nil,
                foregroundColor: finalAccent.isLightColor ? .black : .white
            )
        }
    }

}

#Preview("Smart Badge - Premiere") {
    let container = try! ModelContainer(for: MediaItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let item = MediaItem(id: "sb1", title: "Premiere Show", overview: "", type: .tvShow)
    item.storedSmartBadgeLabel = "PREMIERE"
    item.storedSmartBadgeIsSparkle = true
    context.insert(item)
    return SmartBadgeView(item: item)
}

#Preview("Smart Badge - Behind") {
    let container = try! ModelContainer(for: MediaItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let item = MediaItem(id: "sb2", title: "Behind Show", overview: "", type: .tvShow)
    item.storedSmartBadgeLabel = "BEHIND"
    item.storedProgress = 0.5
    item.remainingEpisodesCount = 5
    context.insert(item)
    return SmartBadgeView(item: item)
}

struct StatusBadgePrimitive: View {
    let label: String
    let accentColor: Color
    let isSolid: Bool
    let progress: Double?
    var isCompact: Bool = false
    var foregroundColor: Color? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let contrastColor = accentColor.highContrastAccent(colorScheme: colorScheme)
        
        HStack(spacing: 0) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(AppTheme.Font.badge)
                    .kerning(1.0)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 20)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor ?? (isSolid ? .white : contrastColor))
        .background(isSolid ? accentColor : accentColor.opacity(colorScheme == .dark ? 0.15 : 0.2))
        .clipShape(Capsule())
        .overlay {
            if let progress = progress, progress > 0 && progress < 1.0 {
                Capsule()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.blueToGreen(progress: progress),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
            }
        }
    }
}
