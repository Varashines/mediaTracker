import SwiftUI
import SwiftData

struct TitleSection: View {
    let item: MediaItem
    let themeColor: Color
    let watchProviders: [WatchProviderResult]
    var onStatusChange: ((MediaState?) -> Void)?
    var logoOptions: [String] = []
    var isCustomLogo: Bool = false
    var onSelectLogo: ((String) -> Void)? = nil
    var onResetLogo: (() -> Void)? = nil
    var onMoodChanged: ((Mood?) -> Void)? = nil
    var accentColor: Color? = nil
    var bgAccentColor: Color? = nil
    @Environment(\.colorScheme) var colorScheme


    @AppStorage("use_title_logos") private var useTitleLogos = true
    @State private var isLogoLight = false
    @State private var isLogosHovering = false
    @State private var showLogoPicker = false
    @State private var showMoodPicker = false

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
                    if useTitleLogos, let logoURL = item.effectiveLogoURL, let url = URL(string: logoURL) {
                        ZStack(alignment: .topTrailing) {
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

                            if logoOptions.count > 1 {
                                Button {
                                    showLogoPicker.toggle()
                                } label: {
                                    Image(systemName: showLogoPicker ? "square.stack.3d.down.right.fill" : "square.stack.3d.down.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .padding(7)
                                        .background {
                                            if showLogoPicker {
                                                Circle().fill(AppTheme.Colors.surfaceSubtle(for: colorScheme))
                                            } else {
                                                Circle().fill(AppThemeCoordinator.isReducingVisualEffects
                                                    ? AnyShapeStyle(AppThemeCoordinator.shared.background(for: colorScheme))
                                                    : AnyShapeStyle(.ultraThinMaterial))
                                            }
                                        }
                                        .shadow(color: .black.opacity(showLogoPicker ? 0.25 : 0.15), radius: showLogoPicker ? 4 : 3, x: 0, y: showLogoPicker ? 3 : 2)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .help("Change logo")
                            .opacity((isLogosHovering || showLogoPicker) ? 1 : 0)
                                .animation(.easeInOut(duration: 0.2), value: isLogosHovering || showLogoPicker)
                                .padding(8)
                                .popover(isPresented: $showLogoPicker) {
                                    LogoPickerGrid(
                                        options: logoOptions,
                                        currentURL: item.effectiveLogoURL,
                                        isCustom: isCustomLogo,
                                        onSelect: { url in
                                            onSelectLogo?(url)
                                            showLogoPicker = false
                                        },
                                        onReset: {
                                            onResetLogo?()
                                            showLogoPicker = false
                                        }
                                    )
                                }
                            }
                        }
                        .onHover { hovering in
                            isLogosHovering = hovering
                        }
                    } else {
                        Text(item.title)
                            .font(AppTheme.Font.largeTitle)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }

                    let creators = !item.cachedCreators.isEmpty 
                        ? item.cachedCreators 
                        : (item.tvShowDetails?.creators ?? [])

                    if !creators.isEmpty {
                        Text("\(item.type == .movie ? "Directed by" : "Created by") \(creators.joined(separator: ", "))")
                            .font(AppTheme.Font.heading)
                            .foregroundStyle(.secondary)
                    }
                }

                // 2. Metadata Badges
                HStack(spacing: AppTheme.Spacing.small) {
                    let accent = accentColor ?? themeColor.highContrastAccent(colorScheme: colorScheme)
                    let bgAccent = bgAccentColor ?? themeColor.luminousAccent(colorScheme: colorScheme)
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
                                    .lineLimit(1)
                                    .truncationMode(.tail)
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
                GlassCard(cornerRadius: AppTheme.Radius.large) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppTheme.Spacing.large) {
                            StatusPicker(item: item, onChange: onStatusChange)

                            Divider().frame(height: 24).opacity(0.3)

                            TasteToggle(item: item, themeColor: themeColor)

                            if (item.taste == .love || item.taste == .like || item.state == .completed) && item.taste != .dislike || item.mood != nil {
                                Divider().frame(height: 24).opacity(0.3)

                                moodButton
                            }
                        }

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            HStack(spacing: AppTheme.Spacing.large) {
                                StatusPicker(item: item, onChange: onStatusChange)

                                Divider().frame(height: 24).opacity(0.3)

                                TasteToggle(item: item, themeColor: themeColor)
                            }

                            if (item.taste == .love || item.taste == .like || item.state == .completed) && item.taste != .dislike || item.mood != nil {
                                Divider().opacity(0.3)
                                moodButton
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.large)
                    .padding(.vertical, AppTheme.Spacing.compact)
                }
            }
        }
    }

    @ViewBuilder
    private var moodButton: some View {
        let currentMood = item.mood.flatMap { Mood.normalized($0) }

        Button {
            showMoodPicker.toggle()
        } label: {
            HStack(spacing: 5) {
                if let mood = currentMood {
                    Image(systemName: mood.emoji)
                        .font(AppTheme.Font.caption2.weight(.semibold))
                        .foregroundStyle(mood.color)
                    Text(mood.rawValue)
                        .font(AppTheme.Font.caption2.weight(.bold))
                } else {
                    Image(systemName: "sparkles")
                        .font(AppTheme.Font.label)
                        .foregroundStyle(themeColor)
                    Text("Add Mood")
                        .font(AppTheme.Font.label)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(currentMood != nil ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(currentMood != nil
                        ? currentMood!.color.opacity(colorScheme == .dark ? 0.20 : 0.12)
                        : AppTheme.Colors.surfaceSubtle(for: colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(
                        currentMood != nil
                            ? currentMood!.color.opacity(0.4)
                            : themeColor.opacity(0.25),
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .hoverScaled(.subtle)
        .popover(isPresented: $showMoodPicker) {
            MoodPickerPopover(
                currentMood: currentMood,
                mediaType: item.type,
                onSelect: { mood in
                    onMoodChanged?(mood)
                    showMoodPicker = false
                },
                onClear: {
                    onMoodChanged?(nil)
                    showMoodPicker = false
                }
            )
        }
    }
}

// MARK: - Mood Picker Popover

private struct MoodPickerPopover: View {
    let currentMood: Mood?
    var mediaType: MediaType? = nil
    let onSelect: (Mood) -> Void
    let onClear: () -> Void
    @State private var hoveredMood: Mood? = nil
    @Environment(\.colorScheme) var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: AppTheme.Spacing.smallMedium) {
            // Header bar
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(AppTheme.Font.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    Text("Select Vibe")
                        .font(AppTheme.Font.label.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if currentMood != nil {
                    Button {
                        onClear()
                    } label: {
                        Text("Reset")
                            .font(AppTheme.Font.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AppTheme.Colors.surfaceGhost(for: colorScheme)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Capsule())
                }
            }

            // 6-Vibe Grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Mood.moods(for: mediaType), id: \.self) { mood in
                    let isSelected = currentMood == mood
                    let isHovered = hoveredMood == mood

                    Button {
                        if isSelected {
                            onClear()
                        } else {
                            onSelect(mood)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(mood.color.opacity(isSelected ? 0.28 : (isHovered ? 0.18 : 0.08)))
                                    .frame(width: 42, height: 42)

                                Image(systemName: mood.emoji)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(mood.color)
                                    .scaleEffect(isHovered ? 1.18 : (isSelected ? 1.08 : 1.0))
                            }
                            .shadow(color: isSelected ? mood.color.opacity(0.4) : (isHovered ? mood.color.opacity(0.25) : .clear), radius: 6, y: 2)

                            Text(mood.rawValue)
                                .font(AppTheme.Font.caption2.weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(isSelected ? mood.color.opacity(colorScheme == .dark ? 0.16 : 0.10) : (isHovered ? AppTheme.Colors.surfaceGhost(for: colorScheme) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .stroke(
                                    isSelected ? mood.color.opacity(0.6) : (isHovered ? mood.color.opacity(0.3) : Color.clear),
                                    lineWidth: isSelected ? 1.5 : 0.5
                                )
                        )
                        .scaleEffect(isHovered ? 1.04 : 1.0)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(AppTheme.Animation.springSnappy) {
                            hoveredMood = hovering ? mood : nil
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(width: 248)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
        }
    }
}

private struct LogoPickerGrid: View {
    let options: [String]
    let currentURL: String?
    let isCustom: Bool
    let onSelect: (String) -> Void
    let onReset: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                Text("Select Logo")
                    .font(AppTheme.Font.label.weight(.semibold))
                Text("·")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(.tertiary)
                Text("\(options.count)")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(options, id: \.self) { urlString in
                        LogoThumbnail(
                            urlString: urlString,
                            isSelected: urlString == currentURL,
                            onSelect: { onSelect(urlString) }
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(maxHeight: min(CGFloat(options.count) * (60 + 8) + 4, 320))

            if isCustom {
                Divider()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)

                Button {
                    onReset()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(AppTheme.Font.caption2)
                        Text("Reset to default")
                            .font(AppTheme.Font.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.Colors.surfaceGhost(for: colorScheme))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 340)
    }
}

private struct LogoThumbnail: View {
    let urlString: String
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var selectionPulse = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let url = URL(string: urlString) {
            CachedImage(url: url, targetSize: CGSize(width: 780, height: 185), priority: .low) { _ in
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
                    .shimmering()
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: isHovered ? 6 : 0, y: isHovered ? 3 : 0)
            .overlay(alignment: .trailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(AppThemeCoordinator.isReducingVisualEffects
                                ? AnyShapeStyle(AppThemeCoordinator.shared.background(for: colorScheme))
                                : AnyShapeStyle(.ultraThinMaterial))
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(AppTheme.Font.caption2.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.trailing, 8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.primary.opacity(0.25) : (isHovered ? Color.secondary.opacity(0.2) : .clear), lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .scaleEffect(selectionPulse ? 0.95 : 1.0)
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    selectionPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        selectionPulse = false
                    }
                }
                onSelect()
            }
        }
    }
}
