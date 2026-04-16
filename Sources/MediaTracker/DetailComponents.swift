import SwiftData
import SwiftUI

struct MediaHeaderView: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    let nextEpisodeText: String?
    var onStatusChange: ((MediaState?) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            PosterView(item: item, themeColor: themeColor)

            VStack(alignment: .leading, spacing: 20) {
                TitleSection(item: item, themeColor: themeColor, onStatusChange: onStatusChange)

                if let nextText = nextEpisodeText {
                    Text(nextText)
                        .foregroundStyle(
                            item.nextAiringDate ?? Date() < Date() ? Color.green : themeColor
                        )
                        .font(.headline)
                        .padding(.top, 4)
                }

                MetadataSection(item: item)

                OverviewSection(overview: item.overview)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color

    var body: some View {
        if let urlString = item.posterURL, let url = URL(string: urlString) {
            ZStack {
                CachedImage(url: url, targetSize: CGSize(width: 600, height: 900)) { _ in
                } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 240, height: 360)
                .clipped()
            }
            .frame(width: 240, height: 360)
            .cornerRadius(12)
            .shadow(color: themeColor.opacity(0.3), radius: 25, x: 0, y: 15) // Deepened ambient shadow
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(themeColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
                    .foregroundStyle(colorScheme == .dark ? .white : themeColor)
                    .clipShape(Capsule())

                if item.isUpcoming {
                    Text("Upcoming")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(colorScheme == .dark ? 0.25 : 0.15))
                        .foregroundStyle(colorScheme == .dark ? .white : .orange)
                        .clipShape(Capsule())
                }

                Spacer().frame(width: 10)

                StatusPicker(state: $item.state, onChange: onStatusChange)
            }
        }
    }
}

struct StatusPicker: View {
    @Binding var state: MediaState?
    var onChange: ((MediaState?) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text("Status:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Status", selection: $state) {
                ForEach(MediaState.allCases, id: \.self) { state in
                    Text(state.displayName).tag(state as MediaState?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .labelsHidden()
            .onChange(of: state) { oldValue, newValue in
                onChange?(newValue)
            }
        }
    }
}

struct MetadataSection: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let movie = item.movieDetails {
                MetadataLine(
                    label: "Release",
                    value: item.releaseDate?.formatted(date: .long, time: .omitted))
                MetadataLine(label: "Runtime", value: DateUtils.formatRuntime(movie.runtime))
                MetadataLine(label: "Genres", value: movie.genres.joined(separator: ", "))
            }

            if let tv = item.tvShowDetails {
                MetadataLine(label: "Status", value: tv.status)
                MetadataLine(label: "Network", value: tv.network)
                if let s = tv.numberOfSeasons, let e = tv.numberOfEpisodes {
                    MetadataLine(label: "Library", value: "\(s) Seasons, \(e) Episodes")
                }
            }

            if let book = item.bookDetails {
                MetadataLine(label: "Author", value: book.authors.joined(separator: ", "))
                MetadataLine(
                    label: "Pages", value: book.pageCount != nil ? "\(book.pageCount!)" : nil)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cast & Crew")
                .font(.title3.bold())
                .padding(.horizontal, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                let sortedCast = cast.sorted(by: { $0.order < $1.order })
                
                LazyHStack(alignment: .center, spacing: 16) {
                    ForEach(sortedCast) { member in
                        CastMemberCardNew(member: member, themeColor: themeColor)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 15)
            }
        }
    }
}

struct CastMemberCardNew: View {
    let member: CastMember
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
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
        .background(.ultraThinMaterial) // Glassmorphism base
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeColor.opacity(colorScheme == .dark ? 0.5 : 0.2), lineWidth: 0.5) // Subtle accent stroke
        )
        .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4) // Ambient accent shadow
    }
}



struct MetadataLine: View {
    let label: String
    let value: String?

    var body: some View {
        if let value = value, !value.isEmpty {
            HStack(spacing: 4) {
                Text("\(label):")
                    .foregroundStyle(.secondary)
                Text(value)
            }
            .font(.subheadline)
        }
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
                    isSelected: item.isLiked == true, color: .green, icon: "hand.thumbsup",
                    label: "Like"
                ) {
                    item.isLiked = true
                }
                RatingButton(
                    isSelected: item.isLiked == false, color: .red, icon: "hand.thumbsdown",
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
    let color: Color
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                Text(label)
            }
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.bordered)
    }
}
