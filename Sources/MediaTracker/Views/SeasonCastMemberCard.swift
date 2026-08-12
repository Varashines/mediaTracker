import SwiftUI
import SwiftData

/// Season cast card styled identically to the top-cast `CastMemberCard`, with
/// the actor's per-season episode count shown as a badge in the lower corner.
struct SeasonCastMemberCard: View {
    let member: SeasonCastMember
    let themeColor: Color
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            action?()
        } label: {
            cardContent
        }
        .buttonStyle(.interactive)
        .accessibilityLabel("\(member.name)\(member.characterName.isEmpty ? "" : ", \(member.characterName)"), \(member.episodeCount) episodes")
    }

    private var cardContent: some View {
        HStack(spacing: 0) {
            imageSection
            textSection
        }
        .frame(width: 200, height: 90)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(AppTheme.Colors.neutralCardFill(for: colorScheme))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .shadow(color: AppTheme.Colors.shadowAmbient(for: colorScheme), radius: AppTheme.Shadow.card.radius, x: AppTheme.Shadow.card.x, y: AppTheme.Shadow.card.y)
        .overlay(borderOverlay())
        .overlay(alignment: .bottomTrailing) {
            episodeCountBadge
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private var episodeCountBadge: some View {
        Text("\(member.episodeCount)")
            .font(AppTheme.Font.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(6)
    }

    @ViewBuilder
    private var imageSection: some View {
        Group {
            if let urlString = member.profileURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 60, height: 90), priority: .low, themeColor: themeColor) { _ in
                } placeholder: {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                        .shimmering()
                }
                .scaledToFill()
            } else {
                ZStack {
                    AppTheme.Colors.surfaceGhost(for: colorScheme)
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(AppTheme.Font.title2)
                }
            }
        }
        .frame(width: 60, height: 90)
        .background(AppTheme.Colors.surfaceGhost(for: colorScheme))
        .clipped()
    }

    @ViewBuilder
    private var textSection: some View {
        let hasCharacterName = !member.characterName.isEmpty

        VStack(alignment: .leading, spacing: hasCharacterName ? AppTheme.Spacing.micro : 0) {
            Text(member.name)
                .font(AppTheme.Font.bodyBold)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)

            if hasCharacterName {
                Text(member.characterName)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.tiny)
        .frame(width: 140, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func borderOverlay() -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10), lineWidth: 0.5)
    }
}
