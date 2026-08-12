import SwiftUI

struct SharePreviewPopup: View {
    let item: MediaItem
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCastIDs: Set<String> = []
    @State private var customShareImage: NSImage? = nil
    @State private var showCustomShareMenu = false

    private var availableCast: [SimpleCastMember] {
        item.displayCast
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

            if availableCast.isEmpty {
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
        .onAppear {
            let initial = Array(availableCast.prefix(3)).map(\.id)
            selectedCastIDs = Set(initial)
        }
    }

    private var cardOnly: some View {
        VStack(spacing: 20) {
            headerRow

            MediaShareCardView(item: item)
                .environment(\.colorScheme, .dark)
                .scaleEffect(0.85)
                .frame(width: 400 * 0.85, height: 700 * 0.85)
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
                    MediaShareCardView(item: item, customCast: selectedCastMembers)
                        .environment(\.colorScheme, .dark)
                        .scaleEffect(0.65)
                        .frame(width: 400 * 0.65, height: 700 * 0.65)
                        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)

                    shareButton {
                        let card = MediaShareCardView(item: item, customCast: selectedCastMembers)
                        if let image = card.renderToImage() {
                            customShareImage = image
                            withAnimation(AppTheme.Animation.springSnappy) { showCustomShareMenu = true }
                        }
                    }
                }
                .frame(width: 290)

                // Right: Cast Selection column (2 columns of 180px wide CastMemberCards)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FEATURED CAST")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .kerning(1.5)
                            .foregroundStyle(.primary.opacity(0.6))

                        Text("Select up to 3 cast members to feature on your card")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

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
                .frame(width: 374)
            }
        }
        .padding(20)
        .frame(width: 730)
        .background(modalBackground)
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
