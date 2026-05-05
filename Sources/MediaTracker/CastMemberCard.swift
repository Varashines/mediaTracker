import SwiftUI
import SwiftData

struct CastMemberCardNew: View {
    let member: SimpleCastMember
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
    }

    @ViewBuilder
    private var cardContent: some View {
        HStack(spacing: 0) {
            imageSection
            textSection
        }
        .frame(width: 200, height: 90)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(borderOverlay)
        .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 6, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .drawingGroup() // Optimize rendering for many cards
    }

    @ViewBuilder
    private var imageSection: some View {
        Group {
            if let urlString = member.profileURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 120, height: 180), priority: .low, themeColor: themeColor) { _ in
                } placeholder: {
                    ProgressView().controlSize(.small)
                }
                .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 24))
                }
            }
        }
        .frame(width: 60, height: 90)
        .background(Color.secondary.opacity(0.1))
        .clipped()
    }

    @ViewBuilder
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(member.characterName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 140, alignment: .leading)
    }

    private var backgroundView: some View {
        AnyView(Rectangle().fill(.thinMaterial))
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(themeColor.opacity(colorScheme == .dark ? 0.4 : 0.2), lineWidth: 1.0)
    }
}
