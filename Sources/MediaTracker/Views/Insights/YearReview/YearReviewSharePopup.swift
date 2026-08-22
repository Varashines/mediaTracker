import SwiftUI
import AppKit
import SwiftData

/// A recap preview with an optional visual editor for its loved-title poster wall.
struct YearReviewSharePopup: View {
    let review: YearInReview
    let onDismiss: () -> Void

    private let previewScale: CGFloat = 0.58

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTitleIDs: [PersistentIdentifier] = []
    @State private var posterImages: [PersistentIdentifier: CGImage] = [:]
    @State private var isPreparing = true
    @State private var showsPicker = false
    @State private var sharedImage: NSImage?
    @State private var showsShareMenu = false

    private var lovedTitles: [YearWatchedTitle] {
        review.lovedCandidates()
    }

    private var selectedTitles: [YearWatchedTitle] {
        selectedTitleIDs.compactMap { selectedID in
            lovedTitles.first { $0.id == selectedID }
        }
    }

    private var posterPickLimit: Int {
        min(8, lovedTitles.count)
    }

    private var totalPickLimit: Int {
        min(10, lovedTitles.count)
    }

    private var automaticTitleIDs: [PersistentIdentifier] {
        lovedTitles.prefix(totalPickLimit).map(\.id)
    }

    private var posterPickCount: Int {
        min(selectedTitleIDs.count, posterPickLimit)
    }

    private var textPickCount: Int {
        max(0, selectedTitleIDs.count - posterPickLimit)
    }

    private var pickerInstruction: String {
        "\(posterPickCount) of \(posterPickLimit) poster picks · \(textPickCount) of \(max(0, totalPickLimit - posterPickLimit)) text picks"
    }

    private var cardHighlights: [YearReviewShareHighlight] {
        selectedTitles.map {
            YearReviewShareHighlight(id: $0.id, title: $0.title, posterImage: posterImages[$0.id])
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            previewPanel

            if showsShareMenu, let sharedImage {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showsShareMenu = false }

                CustomShareMenuView(
                    image: sharedImage,
                    title: "\(review.year) Year in Review",
                    onDismiss: {
                        showsShareMenu = false
                        onDismiss()
                    }
                )
            }
        }
        .task(id: review.year) {
            selectedTitleIDs = automaticTitleIDs
            await loadSelectedPosters()
        }
        .animation(AppTheme.Animation.springGentle, value: showsPicker)
        .animation(AppTheme.Animation.springGentle, value: showsShareMenu)
    }

    private var previewPanel: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            header

            if showsPicker {
                HStack(alignment: .top, spacing: AppTheme.Spacing.large) {
                    cardPreview

                    titlePicker
                        .frame(
                            width: 420,
                            height: YearReviewShareCardView.cardSize.height * previewScale,
                            alignment: .topLeading
                        )
                        .background {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(AppTheme.Colors.surface(for: colorScheme))
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            } else {
                cardPreview
            }

            HStack(spacing: AppTheme.Spacing.small) {
                Button {
                    showsPicker.toggle()
                } label: {
                    Label(showsPicker ? "Done Editing" : "Edit Picks", systemImage: "square.grid.2x2")
                        .font(AppTheme.Font.bodyBold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, AppTheme.Spacing.compact)
                        .background(.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())

                Button(action: exportCard) {
                    Label(
                        isPreparing ? "Preparing…" : "Share Recap",
                        systemImage: isPreparing ? "arrow.triangle.2.circlepath" : "square.and.arrow.up"
                    )
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.compact)
                    .background(AppTheme.Colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .disabled(isPreparing || selectedTitleIDs.count < totalPickLimit)
            }
        }
        .padding(AppTheme.Spacing.large)
        .frame(width: showsPicker ? 830 : 430)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(AppTheme.Colors.background(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .fill(AppTheme.Colors.accent.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        }
    }

    private var cardPreview: some View {
        YearReviewShareCardView(review: review, highlights: cardHighlights)
            .scaleEffect(previewScale)
            .frame(
                width: YearReviewShareCardView.cardSize.width * previewScale,
                height: YearReviewShareCardView.cardSize.height * previewScale
            )
            .shadow(color: .black.opacity(0.55), radius: AppTheme.Spacing.large, y: AppTheme.Spacing.small)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                Text("SHARE YOUR RECAP")
                    .font(AppTheme.Font.caption)
                    .kerning(AppTheme.Kerning.wide)
                    .foregroundStyle(AppTheme.Colors.accent)
                Text("\(review.year) Year in Media")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary, .primary.opacity(0.1))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help("Close")
        }
    }

    @MainActor
    private func loadSelectedPosters() async {
        isPreparing = true
        for title in selectedTitles {
            guard posterImages[title.id] == nil,
                  let posterURL = title.posterURL else {
                continue
            }
            if let image = await ImageCache.shared.get(
                forKey: posterURL,
                targetSize: AppTheme.Thumbnail.small,
                priority: .critical
            )?.image {
                posterImages[title.id] = image
            }
        }
        isPreparing = false
    }

    private var titlePicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("TOP \(totalPickLimit) PICKS")
                        .font(AppTheme.Font.caption)
                        .kerning(AppTheme.Kerning.wide)
                        .foregroundStyle(.secondary)

                    Text(pickerInstruction)
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.secondary)

                    Text("Click a ranked title to remove it.")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Restore Auto") {
                    selectedTitleIDs = automaticTitleIDs
                }
                .buttonStyle(.plain)
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.Colors.accent)
                .contentShape(Rectangle())
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.tiny), count: 3),
                    spacing: AppTheme.Spacing.small
                ) {
                    ForEach(lovedTitles) { title in
                        lovedTitlePickerCell(title)
                    }
                }
                .padding(AppTheme.Spacing.micro)
            }
        }
        .padding(AppTheme.Spacing.small)
    }

    private func lovedTitlePickerCell(_ title: YearWatchedTitle) -> some View {
        let rank = selectedTitleIDs.firstIndex(of: title.id).map { $0 + 1 }
        return Button {
            toggle(title)
        } label: {
            VStack(spacing: AppTheme.Spacing.mini) {
                CachedImage(
                    url: title.posterURL.flatMap(URL.init(string:)),
                    targetSize: AppTheme.Thumbnail.small,
                    priority: .normal
                ) {
                    Color.primary.opacity(0.08)
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(rank == nil ? AppTheme.Colors.strokeDefault(for: colorScheme) : AppTheme.Colors.accent, lineWidth: rank == nil ? 1 : 3)
                    if let rank {
                        Text("#\(rank)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.Spacing.mini)
                            .padding(.vertical, AppTheme.Spacing.micro)
                            .background(AppTheme.Colors.accent, in: Capsule())
                            .padding(AppTheme.Spacing.micro)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }

                Text(title.title)
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(rank == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func toggle(_ title: YearWatchedTitle) {
        if let index = selectedTitleIDs.firstIndex(of: title.id) {
            selectedTitleIDs.remove(at: index)
        } else {
            guard selectedTitleIDs.count < totalPickLimit else { return }
            selectedTitleIDs.append(title.id)
        }
        Task { @MainActor in
            await loadSelectedPosters()
        }
    }

    @MainActor
    private func exportCard() {
        let card = YearReviewShareCardView(review: review, highlights: cardHighlights)
        guard let image = card.renderToImage() else { return }
        sharedImage = image
        showsShareMenu = true
    }
}
