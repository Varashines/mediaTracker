import SwiftData
import SwiftUI

struct MediaHeaderView: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    let nextEpisodeText: String?
    var viewModel: DetailViewModel? = nil
    var namespace: Namespace.ID? = nil
    var onStatusChange: ((MediaState?) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            PosterView(item: item, themeColor: themeColor, namespace: namespace)

            VStack(alignment: .leading, spacing: 20) {
                TitleSection(item: item, themeColor: themeColor, onStatusChange: onStatusChange)

                if let nextText = nextEpisodeText {
                    Text(nextText)
                        .font(.headline)
                        .liquidGlassPill(
                            accentColor: item.nextAiringDate ?? Date() < Date() ? Color.semanticGreen(for: colorScheme) : themeColor,
                            isSolid: item.nextAiringDate ?? Date() < Date()
                        )
                        .padding(.top, 4)
                }

                MetadataSection(item: item, themeColor: themeColor)

                OverviewSection(overview: item.overview)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    var namespace: Namespace.ID? = nil

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            let content = CachedImage(url: url, targetSize: CGSize(width: 600, height: 900)) { _ in
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 240, height: 360)
                .clipped()
            
            Group {
                if let ns = namespace {
                    content
                        .matchedGeometryEffect(id: "poster_\(item.id)", in: ns)
                        .background {
                            Color.clear.matchedGeometryEffect(id: "poster_bg_\(item.id)", in: ns)
                        }
                } else {
                    content
                }
            }
            .frame(width: 240, height: 360)
            .cornerRadius(12)
            .shadow(color: themeColor.opacity(0.3), radius: 25, x: 0, y: 15)  // Deepened ambient shadow
            .zIndex(1)
            .layoutPriority(1)
        }
    }
}

struct TitleSection: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    var onStatusChange: ((MediaState?) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 34, weight: .bold))

            HStack(spacing: 12) {
                Text(item.type?.rawValue ?? "")
                    .font(.subheadline.weight(.semibold))
                    .liquidGlassPill(accentColor: themeColor)

                if item.isUpcoming {
                    Text("Upcoming")
                        .font(.subheadline.weight(.bold))
                        .liquidGlassPill(accentColor: .orange)
                }

                Spacer().frame(width: 10)

                StatusPicker(item: item, onChange: onStatusChange)
            }
        }
    }
}

struct StatusPicker: View {
    @Bindable var item: MediaItem
    var onChange: ((MediaState?) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text("Status:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Status", selection: $item.state) {
                ForEach(availableStates, id: \.self) { state in
                    Text(state.displayName)
                        .tag(state as MediaState?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .labelsHidden()
            .onChange(of: item.state) { oldValue, newValue in
                onChange?(newValue)
            }
        }
    }
    
    private var availableStates: [MediaState] {
        guard item.type == .tvShow else { return MediaState.allCases }
        
        if item.hasWatchedAllEpisodes {
            return [.completed, .rewatching]
        }
        
        if item.hasWatchedAnyEpisode {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        
        return MediaState.allCases
    }
}

struct MetadataSection: View {
    let item: MediaItem
    let themeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let movie = item.movieDetails {
                HStack(spacing: 8) {
                    MetadataLine(label: "Status", value: "Released", themeColor: themeColor)
                    if let lang = movie.originalLanguage {
                        MetadataLine(label: "Language", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                }
                HStack(spacing: 8) {
                    MetadataLine(label: "Genres", value: movie.genres.joined(separator: ", "), themeColor: themeColor)
                    MetadataLine(label: "Runtime", value: DateUtils.formatRuntime(movie.runtime), themeColor: themeColor)
                }
            }

            if let tv = item.tvShowDetails {
                HStack(spacing: 8) {
                    MetadataLine(label: "Status", value: tv.status, themeColor: themeColor)
                    MetadataLine(label: "Network", value: tv.network, themeColor: themeColor)
                    if let lang = tv.originalLanguage {
                        MetadataLine(label: "Language", value: lang, themeColor: themeColor, isLanguage: true)
                    }
                }
                HStack(spacing: 8) {
                    MetadataLine(label: "Genres", value: tv.genres.joined(separator: ", "), themeColor: themeColor)
                    if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                        MetadataLine(label: "Library", value: "\(s) Seasons, \(e) Episodes", themeColor: themeColor)
                    }
                }
            }
        }
    }
}

struct OverviewSection: View {
    let overview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            Text(overview)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CastSectionViewNew: View {
    let cast: [CastMember]
    let themeColor: Color
    var onCastSelected: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cast & Crew")
                .font(.title3.bold())
                .padding(.horizontal, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                let sortedCast = cast.sorted(by: { $0.order < $1.order })

                LazyHStack(alignment: .center, spacing: 16) {
                    ForEach(sortedCast) { member in
                        CastMemberCardNew(member: member, themeColor: themeColor) {
                            onCastSelected?(member.name)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 15)
            }
        }
    }
}

struct CastMemberCardNew: View {
    let member: CastMember
    let themeColor: Color
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 0) {
                // Image Section (Left)
                Group {
                    if let urlString = member.profileURL, let url = URL(string: urlString) {
                        CachedImage(url: url, targetSize: CGSize(width: 120, height: 180)) { _ in
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

                // Text Section (Right)
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
            .frame(width: 200, height: 90)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeColor.opacity(colorScheme == .dark ? 0.4 : 0.2), lineWidth: 1.0)  // Subtle accent stroke
            )
            .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 6, x: 0, y: 3)  // Ambient accent shadow
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct MetadataLine: View {
    let label: String
    let value: String?
    let themeColor: Color
    var isLanguage: Bool = false

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(spacing: 4) {
                Text("\(label):")
                    .foregroundStyle(.secondary)
                Text(displayValue)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 11, weight: .semibold))
            .minimumScaleFactor(0.9)
            .liquidGlassPill(accentColor: themeColor.opacity(0.12), isSolid: false)
        }
    }
    
    private var displayValue: String {
        guard let value = value else { return "" }
        if isLanguage {
            return Locale.current.localizedString(forLanguageCode: value) ?? value.uppercased()
        }
        return value
    }
}

struct RatingSection: View {
    @Bindable var item: MediaItem

    var body: some View {
        HStack(spacing: 40) {
            MyRatingView(item: item)

            if let rating = item.movieDetails?.voteAverage ?? item.tvShowDetails?.voteAverage {
                CommunityRatingView(rating: rating)
            }
        }
    }
}

struct MyRatingView: View {
    @Bindable var item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Rating")
                .font(.headline)

            HStack(spacing: 20) {
                RatingButton(
                    isSelected: item.isLiked == true, type: .like, icon: "hand.thumbsup",
                    label: "Like"
                ) {
                    item.isLiked = true
                }
                RatingButton(
                    isSelected: item.isLiked == false, type: .dislike, icon: "hand.thumbsdown",
                    label: "Dislike"
                ) {
                    item.isLiked = false
                }
            }
        }
    }
}

struct CommunityRatingView: View {
    let rating: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Community Rating")
                .font(.headline)
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text(String(format: "%.1f / 10", rating))
                    .font(.title3.bold())
            }
        }
    }
}

struct RatingButton: View {
    let isSelected: Bool
    let type: RatingType
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    enum RatingType {
        case like, dislike
    }

    private var activeColor: Color {
        switch type {
        case .like: return Color.semanticGreen(for: colorScheme)
        case .dislike: return Color.semanticRed(for: colorScheme)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                Text(label)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : .primary)
            .background {
                if isSelected {
                    activeColor
                } else {
                    Color.primary.opacity(0.05)
                        .background(.ultraThinMaterial)
                }
            }
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
            }
            .shadow(color: isSelected ? activeColor.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}
