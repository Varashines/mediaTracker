import SwiftData
import SwiftUI

struct SharePreviewPopup: View {
    let item: MediaItem
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCastIDs: Set<String> = []
    @State private var selectedSeasonNumber: Int?
    @State private var isLoadingSeasonCast = false
    @State private var customShareImage: NSImage? = nil
    @State private var showCustomShareMenu = false
    @FocusState private var closeButtonFocused: Bool

    private var isTV: Bool {
        item.type == .tvShow
    }

    private var availableSeasons: [TVSeason] {
        guard isTV, let tv = item.tvShowDetails else { return [] }
        return tv.seasons.liveModels
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private var selectedSeason: TVSeason? {
        guard let selectedSeasonNumber else { return nil }
        return availableSeasons.first { $0.seasonNumber == selectedSeasonNumber }
    }

    private var availableCast: [SimpleCastMember] {
        guard isTV, let selectedSeason else { return item.displayCast }
        return selectedSeason.seasonCast.liveModels
            .filter { $0.episodeCount > 0 }
            .sorted {
                if $0.episodeCount == $1.episodeCount {
                    return $0.order < $1.order
                }
                return $0.episodeCount > $1.episodeCount
            }
            .map {
                SimpleCastMember(
                    id: String($0.tmdbPersonID),
                    name: $0.name,
                    characterName: $0.characterName,
                    profileURL: $0.profileURL,
                    order: $0.order
                )
            }
    }

    private var castScopeTitle: String {
        guard let selectedSeasonNumber else { return "Series Cast" }
        return "Season \(selectedSeasonNumber) Cast"
    }

    private var selectedSeasonLabel: String? {
        selectedSeasonNumber.map { "SEASON \($0)" }
    }

    private var selectedCastMembers: [SimpleCastMember] {
        availableCast.filter { selectedCastIDs.contains($0.id) }
    }

    private var shareThemePrimary: Color {
        item.themeColorHex.flatMap { Color(themeHex: $0) } ?? AppTheme.Colors.accent
    }

    private var shareThemeSecondary: Color? {
        item.themeSecondaryColorHex.flatMap { Color(themeHex: $0) }
    }

    private var shareThemeMuted: Color? {
        item.themeMutedColorHex.flatMap { Color(themeHex: $0) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            if availableCast.isEmpty && !isTV {
                cardOnly
            } else {
                sideBySideLayout
            }

            if showCustomShareMenu, let img = customShareImage {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { showCustomShareMenu = false }

                    CustomShareMenuView(
                        image: img,
                        title: item.title,
                        onDismiss: {
                            showCustomShareMenu = false
                            onDismiss()
                        },
                        themeColor: shareThemePrimary,
                        secondaryColor: shareThemeSecondary,
                        mutedColor: shareThemeMuted
                    )
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: showCustomShareMenu)
        .onExitCommand {
            guard !showCustomShareMenu else { return }
            onDismiss()
        }
        .onAppear {
            closeButtonFocused = true
            let initial = Array(availableCast.prefix(3)).map(\.id)
            selectedCastIDs = Set(initial)
        }
        .onChange(of: selectedSeasonNumber) { _, newValue in
            selectedCastIDs = Set(availableCast.prefix(3).map(\.id))
            if let newValue,
               let season = availableSeasons.first(where: { $0.seasonNumber == newValue }) {
                loadSeasonCastIfNeeded(season)
            }
        }
    }

    private var cardOnly: some View {
        VStack(spacing: 20) {
            headerRow

            MediaShareCardView(item: item)
                .environment(\.colorScheme, .dark)
                .scaleEffect(0.85)
                .frame(width: MediaShareCardView.cardSize.width * 0.85, height: MediaShareCardView.cardSize.height * 0.85)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)

            shareButton {
                let card = MediaShareCardView(item: item)
                if let image = card.renderToImage() {
                    customShareImage = image
                    withAnimation(AppTheme.Animation.springSnappy) { showCustomShareMenu = true }
                }
            }
        }
        .padding(24)
        .background(modalBackground)
    }

    private var sideBySideLayout: some View {
        VStack(spacing: 16) {
            headerRow

            HStack(alignment: .top, spacing: 20) {
                // Left: Card column with action button underneath
                VStack(spacing: 14) {
                    MediaShareCardView(item: item, customCast: selectedCastMembers, seasonLabel: selectedSeasonLabel)
                        .environment(\.colorScheme, .dark)
                        .scaleEffect(0.65)
                        .frame(width: MediaShareCardView.cardSize.width * 0.65, height: MediaShareCardView.cardSize.height * 0.65)
                        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)

                    shareButton {
                        let card = MediaShareCardView(item: item, customCast: selectedCastMembers, seasonLabel: selectedSeasonLabel)
                        if let image = card.renderToImage() {
                            customShareImage = image
                            withAnimation(AppTheme.Animation.springSnappy) { showCustomShareMenu = true }
                        }
                    }
                }
                .frame(width: 290)

                // Right: Cast Selection column (2 columns of 180px wide CastMemberCards)
                VStack(alignment: .leading, spacing: 12) {
                    if isTV {
                        castScopeMenu
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("FEATURED CAST")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .kerning(1.5)
                            .foregroundStyle(.primary.opacity(0.6))

                        Text("Select up to 3 cast members to feature on your card")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if isLoadingSeasonCast {
                        HStack(spacing: AppTheme.Spacing.small) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading season cast…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 410)
                    } else if availableCast.isEmpty {
                        ContentUnavailableView(
                            "No cast available",
                            systemImage: "person.2.slash",
                            description: Text("Season cast could not be loaded.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 410)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: [GridItem(.fixed(180), spacing: 10), GridItem(.fixed(180), spacing: 10)], spacing: 10) {
                                ForEach(availableCast, id: \.id) { actor in
                                    let isSelected = selectedCastIDs.contains(actor.id)
                                    CastMemberCard(member: actor, themeColor: isSelected ? AppTheme.Colors.accent : .secondary) {
                                        if isSelected {
                                            selectedCastIDs.remove(actor.id)
                                        } else if selectedCastIDs.count < 3 {
                                            selectedCastIDs.insert(actor.id)
                                        }
                                    }
                                    .scaleEffect(0.9)
                                    .frame(width: 180, height: 81)
                                    .overlay(alignment: .topTrailing) {
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.white, AppTheme.Colors.accent)
                                                .background(Circle().fill(.white).frame(width: 13, height: 13))
                                                .padding(3)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                            .stroke(isSelected ? AppTheme.Colors.accent.opacity(0.6) : .clear, lineWidth: 2)
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.trailing, 4)
                        }
                        .frame(height: 410)
                    }
                }
                .frame(width: 374)
            }
        }
        .padding(20)
        .frame(width: 730)
        .background(modalBackground)
    }

    private var castScopeMenu: some View {
        Picker(
            "Cast",
            selection: Binding(
                get: { selectedSeasonNumber ?? 0 },
                set: { value in
                    selectedSeasonNumber = value == 0 ? nil : value
                }
            )
        ) {
            Text("Series Cast").tag(0)
            ForEach(availableSeasons) { season in
                Text("Season \(season.seasonNumber)").tag(season.seasonNumber)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Cast scope")
        .accessibilityValue(castScopeTitle)
    }

    private func loadSeasonCastIfNeeded(_ season: TVSeason) {
        guard season.seasonCast.isEmpty,
              let tmdbID = item.tvShowDetails?.tmdbID,
              tmdbID > 0 else { return }
        isLoadingSeasonCast = true
        let container = modelContext.container
        Task { @MainActor in
            let service = BackgroundDataService(modelContainer: container)
            await service.refreshSeasonCast(tmdbID: tmdbID, seasonNumber: season.seasonNumber)
            selectedCastIDs = Set(availableCast.prefix(3).map(\.id))
            isLoadingSeasonCast = false
        }
    }

    private var headerRow: some View {
        HStack {
            Text("SHARE COLLECTIBLE CARD")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary, Color.primary.opacity(0.12))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .focused($closeButtonFocused)
            .help("Close")
        }
    }

    private func shareButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Share Card", systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Capsule().fill(AppTheme.Colors.accent))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .shadow(color: AppTheme.Colors.accent.opacity(0.35), radius: 8, y: 4)
    }

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.20), radius: 24, y: 12)
    }
}
