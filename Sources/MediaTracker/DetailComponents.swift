import SwiftUI
import SwiftData

struct MediaHeaderView: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    let nextEpisodeText: String?
    var onStatusChange: ((MediaState?) -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            PosterView(item: item, themeColor: themeColor)
            
            VStack(alignment: .leading, spacing: 20) {
                TitleSection(item: item, onStatusChange: onStatusChange)
                
                if let nextText = nextEpisodeText {
                    Text(nextText)
                        .foregroundStyle(item.nextAiringDate ?? Date() < Date() ? Color.green : Color.accentColor)
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
            CachedImage(url: url, targetSize: nil) { image in
                // Extraction handled in parent via onImageLoaded if needed
            } placeholder: {
                Rectangle().fill(Color.secondary.opacity(0.1))
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 240)
            .cornerRadius(12)
            .shadow(color: themeColor.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}

struct TitleSection: View {
    @Bindable var item: MediaItem
    var onStatusChange: ((MediaState?) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 34, weight: .bold))
            
            HStack(spacing: 12) {
                Text(item.type?.rawValue ?? "")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                if item.isUpcoming {
                    Text("Upcoming")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
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
                MetadataLine(label: "Release", value: item.releaseDate?.formatted(date: .long, time: .omitted))
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
                MetadataLine(label: "Pages", value: book.pageCount != nil ? "\(book.pageCount!)" : nil)
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

struct CastSectionView: View {
    let cast: [CastMember]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.headline)
                .padding(.horizontal, 30)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(cast.sorted(by: { $0.order < $1.order })) { member in
                        CastMemberCard(member: member)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 10)
            }
        }
    }
}

struct CastMemberCard: View {
    let member: CastMember
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if let urlString = member.profileURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: nil) { image in
                    // Profile image loaded
                } placeholder: {
                    Circle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 70, height: 70)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 30))
                    )
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            
            VStack(alignment: .center, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(member.characterName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 90)
        }
        .frame(width: 90, alignment: .top)
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
                RatingButton(isSelected: item.isLiked == true, color: .green, icon: "hand.thumbsup", label: "Like") {
                    item.isLiked = true
                }
                RatingButton(isSelected: item.isLiked == false, color: .red, icon: "hand.thumbsdown", label: "Dislike") {
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
