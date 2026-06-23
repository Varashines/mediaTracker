import SwiftUI
import SwiftData

struct CastMemberCard: View {
    let member: SimpleCastMember
    let themeColor: Color
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false


    var body: some View {
        Button {
            action?()
        } label: {
            cardContent
        }
        .buttonStyle(.interactive)
        .shadow(color: AppTheme.Colors.shadowElevated(for: colorScheme), radius: isHovered ? 8 : 2, y: isHovered ? 4 : 1)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(member.name)\(member.characterName.isEmpty ? "" : ", \(member.characterName)")")
    }

    @ViewBuilder
    private var cardContent: some View {
        HStack(spacing: 0) {
            imageSection
            textSection
        }
        .frame(width: 200, height: 90)
        .background(AppTheme.Colors.surfaceSubtle(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .overlay(borderOverlay())
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    @ViewBuilder
    private var imageSection: some View {
        Group {
            if let urlString = member.profileURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 60, height: 90), priority: .low, themeColor: themeColor) { _ in
                } placeholder: {
                    ProgressView().controlSize(.small)
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
