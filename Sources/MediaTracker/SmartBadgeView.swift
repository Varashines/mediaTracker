import SwiftUI
import SwiftData

struct SmartBadgeView: View {
    let item: MediaItem?
    let metadata: MediaThumbnailMetadata?
    let result: MediaSearchResult?
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic

    init(item: MediaItem) {
        self.item = item
        self.metadata = nil
        self.result = nil
    }
    
    init(metadata: MediaThumbnailMetadata) {
        self.item = nil
        self.metadata = metadata
        self.result = nil
    }

    init(result: MediaSearchResult) {
        self.item = nil
        self.metadata = nil
        self.result = result
    }

    var body: some View {
        if let metadata = metadata {
            if let label = metadata.smartBadgeLabel, let icon = metadata.smartBadgeIcon {
                intelligentBadge(label: label, icon: icon, isSparkle: metadata.isSparkleBadge, remaining: metadata.remainingCount)
            } else if metadata.type == .movie {
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
                intelligentBadge(label: label, icon: icon, isSparkle: item.storedSmartBadgeIsSparkle, remaining: item.remainingEpisodesCount)
            } else if item.type == .movie {
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
    private func intelligentBadge(label: String, icon: String, isSparkle: Bool, remaining: Int? = nil) -> some View {
        let isBinge = label == "BINGE"
        
        let badgeConfig: (bg: Color, fg: Color) = {
            switch label {
            case "SERIES PREMIERE", "SEASON PREMIERE", "FINALE":
                // Milestones: Electric Purple
                return (Color(red: 0.4, green: 0.3, blue: 0.9), .white)
            case "BINGE", "BINGE DROP":
                // Binge: Teal/Mint
                return (Color(red: 0.0, green: 0.6, blue: 0.5), .white)
            case "NEW", "SOON":
                // Release: Solar Orange
                return (Color.orange, .white)
            case "CATCH UP":
                // Engagement: Slate Blue
                return (Color(red: 0.3, green: 0.4, blue: 0.6), .white)
            case "RECENT":
                // Fallback: Translucent Gray
                return (Color.secondary.opacity(0.8), .white)
            default:
                return (Color.secondary.opacity(0.8), .white)
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: icon)
            
            if isBinge, let remaining = remaining, remaining > 0 {
                HStack(spacing: 4) {
                    Text("BINGE")
                    Text("•")
                        .opacity(0.5)
                    Text("\(remaining) LEFT")
                        .font(.system(size: 8, weight: .heavy))
                }
            } else {
                Text(label)
            }
        }
        .font(.system(size: 9, weight: .black))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeConfig.bg.gradient)
        .foregroundStyle(badgeConfig.fg)
        .clipShape(Capsule())
        .shadow(color: isSparkle ? badgeConfig.bg.opacity(0.5) : .black.opacity(0.1), radius: isSparkle ? 6 : 3, y: 2)
        .overlay {
            if isSparkle {
                Capsule()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
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

        // 2. Determine Display Label
        let displayLabel = nextEpisodeLabel ?? watchProgressLabel ?? currentState.displayName

        // 3. Determine Icon
        let icon = isAvailable ? "play.fill" : (isUpcoming ? "sparkles" : currentState.iconName)

        // 4. Pill Logic
        let isInProgress = (currentState == .active || currentState == .rewatching)
        let hasEpisodeStats = nextEpisodeLabel != nil
        let showFullPill = (isUpcoming && hasEpisodeStats) || (!isUpcoming && isInProgress)

        // 5. Progress Bar
        let showProgressBar = !isUpcoming && isInProgress

        return StatusBadgePrimitive(
            label: displayLabel,
            systemImage: icon,
            accentColor: isAvailable ? appAccent.color : .primary,
            isSolid: isAvailable,
            progress: showProgressBar ? progress : nil,
            isCompact: !showFullPill
        )
        .opacity(currentState == .completed ? 0 : 1)
    }

}
