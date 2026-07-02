import SwiftUI
import SwiftData

struct TitleSection: View {
    let item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    var onStatusChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme


    @AppStorage("use_title_logos") private var useTitleLogos = true
    @State private var isLogoLight = false

    private func cleanProviderName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("netflix") { return "NETFLIX" }
        if lower.contains("disney") { return "DISNEY+" }
        if lower.contains("hotstar") { return "HOTSTAR" }
        if lower.contains("prime video") || lower.contains("amazon prime") { return "PRIME VIDEO" }
        if lower.contains("apple tv") { return "APPLE TV+" }
        if lower.contains("hulu") { return "HULU" }
        if lower.contains("max") || lower.contains("hbo") { return "MAX" }
        if lower.contains("paramount") { return "PARAMOUNT+" }
        if lower.contains("peacock") { return "PEACOCK" }
        if lower.contains("crunchyroll") { return "CRUNCHYROLL" }
        if lower.contains("zee5") { return "ZEE5" }
        if lower.contains("sony") { return "SONYLIV" }
        if lower.contains("jio") { return "JIOCINEMA" }
        return name.uppercased()
    }

    private func providersText(_ providers: [WatchProviderResult]) -> String {
        let names = providers.map { cleanProviderName($0.name) }
        guard !names.isEmpty else { return "" }
        if names.count == 1 {
            return names[0]
        } else if names.count == 2 {
            return "\(names[0]) & \(names[1])"
        } else {
            return names.joined(separator: ", ")
        }
    }

    private func formatUpcomingDate(_ date: Date, isMovie: Bool) -> String {
        let now = Date()
        let calendar = Calendar.current

        if isMovie {
            // Movies: no time, just date
            if calendar.isDateInToday(date) {
                return "Releasing today"
            } else if calendar.isDateInTomorrow(date) {
                return "Releasing tomorrow"
            } else if let daysUntil = calendar.dateComponents([.day], from: now, to: date).day, daysUntil <= 6 {
                let weekday = date.formatted(.dateTime.weekday(.wide))
                return "Releasing on \(weekday)"
            } else {
                return "Releasing on \(date.formatted(date: .abbreviated, time: .omitted))"
            }
        } else {
            // TV shows: with time
            if calendar.isDateInToday(date) {
                return "Today \(date.formatted(date: .omitted, time: .shortened))"
            } else if calendar.isDateInTomorrow(date) {
                return "Tomorrow \(date.formatted(date: .omitted, time: .shortened))"
            } else if let daysUntil = calendar.dateComponents([.day], from: now, to: date).day, daysUntil <= 6 {
                let weekday = date.formatted(.dateTime.weekday(.wide))
                return "\(weekday) \(date.formatted(date: .omitted, time: .shortened))"
            } else {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
        }
    }

    var body: some View {
        if item.modelContext != nil {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                // 1. Editorial Title & Creators
                VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
                    if useTitleLogos, let logoURL = item.titleLogoURL, let url = URL(string: logoURL) {
                        CachedImage(url: url, targetSize: CGSize(width: 780, height: 185), priority: .critical) { cgImage in
                            Task.detached(priority: .utility) {
                                let dominant = await ColorExtractor.dominantColor(from: cgImage)
                                await MainActor.run {
                                    self.isLogoLight = dominant.isNearlyWhite
                                }
                            }
                        } placeholder: {
                            Text(item.title)
                                .font(AppTheme.Font.largeTitle)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 110, alignment: .leading)
                        .colorInvert(colorScheme == .light && isLogoLight)
                    } else {
                        Text(item.title)
                            .font(AppTheme.Font.largeTitle)
                            .lineLimit(3)
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

                    // Upcoming pill (TV shows and movies)
                    let upcomingDate: Date? = {
                        if item.type == .tvShow { return item.cachedNextAiringDate }
                        if item.type == .movie { return item.releaseDate }
                        return nil
                    }()
                    if let nextDate = upcomingDate, nextDate > Date() {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(AppTheme.Font.tiny)
                            if let epLabel = item.storedNextEpisodeLabel {
                                Text(epLabel.uppercased())
                                    .font(AppTheme.Font.caption2)
                                    .kerning(AppTheme.Kerning.wide)
                                Text("·")
                                    .foregroundStyle(.secondary)
                            }
                            Text(formatUpcomingDate(nextDate, isMovie: item.type == .movie).uppercased())
                                .font(AppTheme.Font.caption2)
                                .kerning(AppTheme.Kerning.wide)
                        }
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.micro)
                        .foregroundStyle(accent)
                        .background {
                            Capsule()
                                .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.10))
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(accent.opacity(0.1), lineWidth: 0.5)
                        }
                    }

                    // Watch providers — tappable to open TMDB watch page
                    if !watchProviders.isEmpty, let watchURL = watchProviders.first?.watchPageURL, let url = URL(string: watchURL) {
                        Button {
                            #if os(macOS)
                            NSWorkspace.shared.open(url)
                            #endif
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "popcorn.fill")
                                    .font(AppTheme.Font.tiny)
                                Text(providersText(watchProviders))
                                    .font(AppTheme.Font.caption2)
                                    .kerning(AppTheme.Kerning.wide)
                            }
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
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
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
