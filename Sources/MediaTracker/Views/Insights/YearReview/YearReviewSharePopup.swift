import SwiftUI
import SwiftData

struct YearReviewSharePopup: View {
    let review: YearInReview
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFavoriteIDs: Set<PersistentIdentifier> = []
    @State private var customShareImage: NSImage? = nil
    @State private var showCustomShareMenu = false

    private var availableFavorites: [YearWatchedTitle] {
        let favorites = review.favoriteCandidates()
        return favorites.isEmpty ? review.allWatchedTitles() : favorites
    }

    private var selectedFavorites: [YearWatchedTitle] {
        let available = availableFavorites
        return available.filter { selectedFavoriteIDs.contains($0.id) }
    }

    private var shareThemePrimary: Color {
        Color(red: 0.55, green: 0.35, blue: 0.95)
    }

    private var shareThemeSecondary: Color {
        Color(red: 0.15, green: 0.75, blue: 0.95)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            sideBySideLayout

            if showCustomShareMenu, let img = customShareImage {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { showCustomShareMenu = false }

                    CustomShareMenuView(
                        image: img,
                        title: "\(review.year)_Year_In_Review",
                        onDismiss: {
                            showCustomShareMenu = false
                            onDismiss()
                        },
                        themeColor: shareThemePrimary,
                        secondaryColor: shareThemeSecondary,
                        mutedColor: Color(red: 0.95, green: 0.35, blue: 0.55)
                    )
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Animation.springSnappy, value: showCustomShareMenu)
    }

    private var sideBySideLayout: some View {
        VStack(spacing: 16) {
            headerRow

            HStack(alignment: .top, spacing: 20) {
                // Left Column: Live Scaled Card Preview + Action Button
                VStack(spacing: 14) {
                    YearReviewShareCardView(review: review, selectedFavorites: selectedFavorites)
                        .environment(\.colorScheme, .dark)
                        .scaleEffect(0.62)
                        .frame(
                            width: YearReviewShareCardView.cardSize.width * 0.62,
                            height: YearReviewShareCardView.cardSize.height * 0.62
                        )
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                    shareButton {
                        let card = YearReviewShareCardView(review: review, selectedFavorites: selectedFavorites)
                        if let image = card.renderToImage() {
                            customShareImage = image
                            withAnimation(AppTheme.Animation.springSnappy) { showCustomShareMenu = true }
                        }
                    }
                }
                .frame(width: 290)

                // Right Column: Favorites Selection List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("FAVORITE PICKS OF \(String(review.year))")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .kerning(1.5)
                                .foregroundStyle(shareThemePrimary)

                            Text(
                                selectedFavoriteIDs.isEmpty
                                    ? "Select up to 3 favorites to highlight on your card"
                                    : "\(selectedFavoriteIDs.count)/3 selected"
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !selectedFavoriteIDs.isEmpty {
                            Button("Clear") {
                                selectedFavoriteIDs.removeAll()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(shareThemeSecondary)
                            .buttonStyle(.plain)
                        }
                    }

                    if availableFavorites.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "film")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("No watched titles to select")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: 380)
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 8) {
                                ForEach(availableFavorites) { item in
                                    let isSelected = selectedFavoriteIDs.contains(item.id)
                                    favoriteRow(item: item, isSelected: isSelected) {
                                        if isSelected {
                                            selectedFavoriteIDs.remove(item.id)
                                        } else if selectedFavoriteIDs.count < 3 {
                                            selectedFavoriteIDs.insert(item.id)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.trailing, 4)
                        }
                        .frame(width: 320, height: 400)
                    }
                }
            }
        }
        .padding(22)
        .background(modalBackground)
    }

    private func favoriteRow(item: YearWatchedTitle, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Poster
                if let posterURL = item.posterURL.flatMap(URL.init) {
                    CachedImage(url: posterURL, targetSize: .thumbSmall) { _ in } placeholder: {
                        Rectangle().fill(Color.primary.opacity(0.08))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 30, height: 44)
                        Image(systemName: item.type == .tvShow ? "tv" : "film")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Title & Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(item.type == .tvShow ? "TV Series" : "Movie")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if item.tasteValue == "Love" || item.tasteValue == "Loved" {
                            Text("❤️ Loved")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.55))
                        } else if item.tasteValue == "Like" || item.tasteValue == "Liked" {
                            Text("👍 Liked")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.4))
                        }
                    }
                }

                Spacer(minLength: 4)

                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? shareThemePrimary : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 18, height: 18)

                    if isSelected {
                        Circle()
                            .fill(shareThemePrimary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? shareThemePrimary.opacity(0.12) : AppTheme.Colors.surface(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? shareThemePrimary.opacity(0.5) : AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var headerRow: some View {
        HStack {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [shareThemePrimary, shareThemeSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)

                Text("\(String(review.year)) WRAPPED CARD")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .kerning(1.8)
                    .foregroundStyle(shareThemePrimary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary, .quaternary)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
    }

    private func shareButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                Text("Export Wrapped Card")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [shareThemePrimary, shareThemeSecondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: shareThemePrimary.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var modalBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.Colors.background(for: colorScheme))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [shareThemePrimary.opacity(0.4), shareThemeSecondary.opacity(0.2), AppTheme.Colors.strokeDefault(for: colorScheme)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
    }
}
