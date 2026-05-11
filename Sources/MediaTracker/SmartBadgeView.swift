import SwiftUI
import SwiftData

struct SmartBadgeView: View {
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    let hideEpisodeProgress: Bool
    let themeColorOverride: Color?
    
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard

    init(item: MediaItem, hideEpisodeProgress: Bool = false, themeColor: Color? = nil) {
        self.item = item
        self.metadata = nil
        self.result = nil
        self.hideEpisodeProgress = hideEpisodeProgress
        self.themeColorOverride = themeColor
    }
    
    init(metadata: MediaThumbnailMetadata, hideEpisodeProgress: Bool = false, themeColor: Color? = nil) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
        self.hideEpisodeProgress = hideEpisodeProgress
        self.themeColorOverride = themeColor
    }

    init(result: MediaSearchResult, hideEpisodeProgress: Bool = false) {
        self.item = nil
        self.metadata = nil
        self.result = result
        self.hideEpisodeProgress = hideEpisodeProgress
        self.themeColorOverride = nil
    }

    var body: some View {
        if let metadata = metadata {
            if let label = metadata.smartBadgeLabel, let icon = metadata.smartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: metadata.isSparkleBadge, remaining: metadata.remainingCount, progress: metadata.progress)
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
            if let label = item.storedSmartBadgeLabel, let icon = item.storedSmartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: item.storedSmartBadgeIsSparkle, remaining: item.remainingEpisodesCount, progress: item.storedProgress)
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
             statusUI(isUpcoming: false, state: .wishlist, badgeText: nil, watchProgressLabel: nil, nextEpisodeLabel: nil, progress: nil)
        }
    }

    @ViewBuilder
    private func intelligentBadge(label: String, icon: String, isSparkle: Bool, remaining: Int? = nil, progress: Double? = nil) -> some View {
        let badgeConfig: (bg: Color, fg: Color) = {
            switch label {
            case "SERIES PREMIERE":
                // Series Premiere: Deep Ultraviolet
                return (Color.fromOKLCH(l: 0.55, c: 0.25, h: 280), .white)
            case "SEASON PREMIERE":
                // Season Premiere: Electric Orchid
                return (Color.fromOKLCH(l: 0.6, c: 0.22, h: 310), .white)
            case "FINALE":
                // Finale: Vibrant Rose (Premium shift away from yellow)
                return (Color.fromOKLCH(l: 0.62, c: 0.24, h: 340), .white)
            case "BINGE":
                if isSparkle {
                    // Active Binge (Hot Streak): Lava Red
                    return (Color.fromOKLCH(l: 0.6, c: 0.28, h: 25), .white)
                } else {
                    // Backlog Binge: Deep Indigo
                    return (Color.fromOKLCH(l: 0.45, c: 0.18, h: 260), .white)
                }
            case "BINGE DROP":
                // Binge Drop: Electric Cyan/Teal
                return (Color.fromOKLCH(l: 0.7, c: 0.15, h: 190), .white)
            case "NEW":
                // New: Luminous Mint
                return (Color.fromOKLCH(l: 0.75, c: 0.18, h: 150), .black)
            case "SOON":
                // Soon: Luminous Tangerine
                return (Color.fromOKLCH(l: 0.7, c: 0.2, h: 45), .black)
            case "CATCH UP":
                // Engagement: Slate Blue
                return (Color.fromOKLCH(l: 0.55, c: 0.12, h: 240), .white)
            case "RECENT":
                // Fallback: Translucent Gray
                return (Color.secondary.opacity(0.8), .white)
            default:
                return (Color.secondary.opacity(0.8), .white)
            }
        }()

        StatusBadgePrimitive(
            label: label,
            systemImage: icon,
            accentColor: badgeConfig.bg,
            isSolid: true,
            progress: progress,
            isCompact: true,
            foregroundColor: badgeConfig.fg
        )
        .shadow(color: isSparkle ? badgeConfig.bg.opacity(0.5) : .black.opacity(0.1), radius: isSparkle ? 6 : 3, y: 2)
        .overlay {
            if isSparkle {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 24, height: 24)
            }
        }
    }

    private func statusUI(
        isUpcoming: Bool,
        state: MediaState?,
        badgeText: String?,
        watchProgressLabel: String?,
        nextEpisodeLabel: String?,
        progress: Double?
    ) -> some View {
        let currentState = state ?? .wishlist

        // 1. Determine Availability
        let badge = badgeText ?? ""
        let isAvailable = isUpcoming && (badge.contains("Streaming") || badge.contains("Available"))

        // 2. Determine Display Label (Used for accessibility, hidden in compact UI)
        let displayLabel = currentState.displayName

        // 3. Determine Icon
        let icon = isAvailable ? "play.fill" : (isUpcoming ? "sparkles" : currentState.iconName)

        // 4. Progress Logic
        let isInProgress = (currentState == .active || currentState == .rewatching)
        let showProgressBar = !hideEpisodeProgress && !isUpcoming && isInProgress

        let finalAccent: Color = {
            if let override = themeColorOverride {
                return override
            }
            return themeStyle == .brand ? appAccent.color : .blue
        }()

        return StatusBadgePrimitive(
            label: displayLabel,
            systemImage: icon,
            accentColor: isAvailable ? finalAccent : .primary,
            isSolid: isAvailable,
            progress: showProgressBar ? progress : nil,
            isCompact: true, // Force circular for premium grid consistency
            foregroundColor: isAvailable ? (finalAccent.isLightColor ? .black : .white) : nil
        )
        .opacity(currentState == .completed ? 0 : 1)
    }

}
