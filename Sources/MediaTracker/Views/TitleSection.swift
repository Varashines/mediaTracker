import SwiftUI
import SwiftData

struct TitleSection: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    var onStatusChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme


    @State private var isLogoLight = false

    var body: some View {
        if item.modelContext != nil {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                // 1. Editorial Title & Creators
                VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                    if let logoURL = item.titleLogoURL, let url = URL(string: logoURL) {
                        CachedImage(url: url, targetSize: CGSize(width: 780, height: 185), priority: .critical) { cgImage in
                            Task {
                                let dominant = await ColorExtractor.dominantColor(from: cgImage)
                                await MainActor.run {
                                    self.isLogoLight = dominant.isNearlyWhite
                                }
                            }
                        } placeholder: {
                            Text(item.title)
                                .font(AppTheme.Font.largeTitle)
                                .lineLimit(3)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(.primary)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 110, alignment: .leading)
                        .colorInvert(colorScheme == .light && isLogoLight)
                    } else {
                        Text(item.title)
                            .font(AppTheme.Font.largeTitle)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.primary)
                    }

                    let creators = item.cachedCreators
                    if !creators.isEmpty {
                        Text("\(item.type == .movie ? "Directed by" : "Created by") \(creators.joined(separator: ", "))")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.secondary)
                    }
                }

                // 2. Metadata Badges
                HStack(spacing: AppTheme.Spacing.small) {
                    let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
                    let bgAccent = themeColor.luminousAccent(colorScheme: colorScheme)
                    
                    Text(item.type?.rawValue.uppercased() ?? "")
                        .font(AppTheme.Font.caption2)
                        .kerning(AppTheme.Kerning.wide)
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.micro)
                        .foregroundStyle(accent)
                        .background {
                            Capsule()
                                .fill(bgAccent.opacity(colorScheme == .dark ? 0.25 : 0.30))
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(accent.opacity(0.1), lineWidth: 0.5)
                        }

                    // TMDB Status pill (beside TV SHOW/MOVIE pill)
                    if let status = item.cachedTMDBStatus, !status.isEmpty {
                        Text(status.uppercased())
                            .font(AppTheme.Font.caption2)
                            .kerning(AppTheme.Kerning.wide)
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.micro)
                            .foregroundStyle(accent)
                            .background {
                                Capsule()
                                    .fill(accent.opacity(0.12))
                            }
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(accent.opacity(0.1), lineWidth: 0.5)
                            }
                    }

                    if item.isUpcoming, let dateText = item.detailBadgeText {
                        let isStreaming = (item.cachedNextAiringDate ?? Date()) < Date()
                        let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
                        HStack(spacing: AppTheme.Spacing.micro) {
                            Image(systemName: isStreaming ? "play.fill" : "calendar")
                                .font(AppTheme.Font.tiny)
                            Text(dateText.uppercased())
                                .font(AppTheme.Font.caption2)
                                .kerning(AppTheme.Kerning.wide)
                        }
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.micro)
                        .foregroundStyle(accent)
                        .background {
                            Capsule()
                                .fill(accent.opacity(0.15))
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(accent.opacity(0.15), lineWidth: 0.5)
                        }
                    }
                }
                
                // 3. Unified Glass Action Bar
                HStack(spacing: AppTheme.Spacing.large) {
                    StatusPicker(item: item, onChange: onStatusChange)
                    
                    Divider().frame(height: 24).opacity(0.3)
                    
                    TasteToggle(item: item, themeColor: themeColor)
                }
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.vertical, AppTheme.Spacing.compact)
                .background {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous).fill(.ultraThinMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: AppTheme.Colors.shadowAmbient(for: colorScheme), radius: 10, y: 5)
            }
        }
    }
}
