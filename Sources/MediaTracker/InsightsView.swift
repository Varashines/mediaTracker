import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var insights: TasteInsights?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) {
                if isLoading {
                    ProgressView("Analyzing your library...")
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else if let insights = insights {
                    // 1. Profile Header
                    profileHeader(insights: insights)
                    
                    // 2. Top Genres (Simple List)
                    if !insights.genreAffinities.isEmpty {
                        genreSection(data: insights.genreAffinities)
                    }

                    // 3. Creative Visionaries (Top 10 Directors)
                    if !insights.creatorAffinities.isEmpty {
                        personSection(title: "Creative Visionaries", data: insights.creatorAffinities, color: .blue)
                    }
                    
                    // 4. Recurring Stars (Top 10 Cast)
                    if !insights.castAffinities.isEmpty {
                        personSection(title: "Recurring Stars", data: insights.castAffinities, color: .orange)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .onAppear {
            refreshData()
        }
    }

    private func refreshData() {
        Task {
            let actor = TasteActor(modelContainer: modelContext.container)
            let result = await actor.fetchTasteInsights()
            await MainActor.run {
                self.insights = result
                self.isLoading = false
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func profileHeader(insights: TasteInsights) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Taste Profile")
                .font(.system(size: 44, weight: .black, design: .rounded))
            
            HStack(spacing: 20) {
                summaryTile(label: "Top Genre", value: insights.genreAffinities.first?.name ?? "N/A", color: .purple)
                summaryTile(label: "Key Director", value: insights.creatorAffinities.first?.name ?? "N/A", color: .blue)
                summaryTile(label: "Main Star", value: insights.castAffinities.first?.name ?? "N/A", color: .orange)
            }
        }
    }

    @ViewBuilder
    private func summaryTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .cornerRadius(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func genreSection(data: [(name: String, affinity: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Top Genres", icon: "film.stack", iconColor: appAccent.color)
            
            PillGrid(items: data.prefix(12).map { $0.name }, color: appAccent.color)
                .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private func personSection(title: String, data: [(name: String, affinity: Double, imageURL: String?)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: title, icon: color == .blue ? "person.2.badge.gearshape" : "star.fill", iconColor: color)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(data.prefix(10), id: \.name) { entry in
                        InsightPersonCard(name: entry.name, imageURL: entry.imageURL, color: color)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 40)
            }
        }
    }
}

struct InsightPersonCard: View {
    let name: String
    let imageURL: String?
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Image Section (Left)
            Group {
                if let urlString = imageURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 160, height: 220), priority: .low, themeColor: color) { _ in
                    } placeholder: {
                        Rectangle().fill(color.opacity(0.1))
                            .overlay { ProgressView().controlSize(.small) }
                    }
                    .scaledToFill()
                } else {
                    ZStack {
                        color.opacity(0.1)
                        Image(systemName: "person.fill")
                            .foregroundStyle(color.opacity(0.5))
                            .font(.system(size: 30))
                    }
                }
            }
            .frame(width: 80, height: 110)
            .clipped()

            // Text Section (Right)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Text("Top Contributor")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 160, height: 110, alignment: .leading)
        }
        .frame(width: 240, height: 110)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(colorScheme == .dark ? 0.3 : 0.1), lineWidth: 1.0)
        )
    }
}

struct PillGrid: View {
    let items: [String]
    let color: Color
    
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(color.opacity(0.1))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(color.opacity(0.2), lineWidth: 1)
                    }
            }
        }
    }
}
