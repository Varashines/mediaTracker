import SwiftUI
import SwiftData

struct DiscoveryHubView: View {
    @Environment(\.modelContext) private var modelContext
    let namespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    let onFilterSelected: (DiscoveryFilter) -> Void
    
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var hasDataLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 60) { // Increased spacing for scale effect
                if hasDataLoaded {
                    // 1. Networks / Studios (Full Grid)
                    DiscoverySection(title: "Networks & Studios", icon: "tv", nodes: viewModel.cachedNetworks, style: .logo) { node in
                        onFilterSelected(DiscoveryFilter(type: .studio, name: node.name))
                    }
                    .padding(.top, 40)

                    // 2. Genres (Full Grid)
                    DiscoverySection(title: "Genres", icon: "film", nodes: viewModel.cachedGenres, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .genre, name: node.name))
                    }

                    // 3. Languages (Full Grid)
                    DiscoverySection(title: "Languages", icon: "globe", nodes: viewModel.cachedLanguages, style: .text) { node in
                        onFilterSelected(DiscoveryFilter(type: .language, name: node.id))
                    }
                } else {
                    // Loading State
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 100)
                }
            }
            .padding(.bottom, 100)
            // Essential: Prevent clipping during scaling
            .scrollTargetLayout()
        }
        .onAppear { refreshData(force: false) }
        .refreshable { refreshData(force: true) }
    }
    
    private func refreshData(force: Bool) {
        if !force, hasDataLoaded, let last = viewModel.lastDiscoveryRefresh, Date().timeIntervalSince(last) < 600 {
            return
        }
        
        let container = modelContext.container
        let localHidden = hiddenStudios
        
        if force && viewModel.discoverySyncService == nil {
            viewModel.discoverySyncService = DiscoverySyncService(modelContainer: container)
        }

        let syncService = viewModel.discoverySyncService

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            if force { await syncService?.syncLibrary(force: true) }
            
            let netDescriptor = FetchDescriptor<NetworkEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let genreDescriptor = FetchDescriptor<GenreEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            let langDescriptor = FetchDescriptor<LanguageEntity>(sortBy: [SortDescriptor(\.count, order: .reverse)])
            
            let nets = (try? context.fetch(netDescriptor)) ?? []
            let hiddenSet = Set(localHidden.components(separatedBy: ",").filter { !$0.isEmpty })
            let filteredNets = nets.filter { !hiddenSet.contains($0.name) }
            
            let snNets = filteredNets.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex) }
            let snGenres = ((try? context.fetch(genreDescriptor)) ?? []).map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) }
            let snLangs = ((try? context.fetch(langDescriptor)) ?? []).map { 
                let name = LanguageUtils.languageName(for: $0.code)
                return DiscoveryNode(name: name, code: $0.code, logoPath: nil, count: $0.count) 
            }
            
            await MainActor.run {
                withAnimation(.smooth(duration: 0.5)) {
                    self.viewModel.lastDiscoveryRefresh = Date()
                    self.viewModel.cachedNetworks = snNets
                    self.viewModel.cachedGenres = snGenres
                    self.viewModel.cachedLanguages = snLangs
                    self.hasDataLoaded = true
                }
            }
        }
    }
}

// MARK: - Rich Grid Components

enum DiscoveryCardStyle {
    case logo, text
}

struct DiscoverySection: View {
    let title: String
    let icon: String
    let nodes: [DiscoveryNode]
    let style: DiscoveryCardStyle
    let onSelected: (DiscoveryNode) -> Void
    
    // Responsive Grid with enough spacing for 1.1x scaling
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 30)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 40)
            
            LazyVGrid(columns: columns, spacing: 30) {
                ForEach(nodes) { node in
                    DiscoveryCard(node: node, style: style) { onSelected(node) }
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

struct DiscoveryCard: View {
    let node: DiscoveryNode
    let style: DiscoveryCardStyle
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isAppeared = false
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background: Inverted Asymmetric Oval Shape
                UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 35, bottomTrailingRadius: 15, topTrailingRadius: 35)
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .overlay {
                        if let hex = node.themeColorHex, let color = Color(hex: hex) {
                            color.opacity(isHovered ? 0.25 : 0.05)
                        }
                    }
                
                if style == .logo {
                    logoContent
                } else {
                    textContent
                }
            }
            .frame(height: 90)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 35, bottomTrailingRadius: 15, topTrailingRadius: 35))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 35, bottomTrailingRadius: 15, topTrailingRadius: 35)
                    .stroke(isHovered ? appAccent.color.opacity(0.6) : Color.clear, lineWidth: 2)
            }
            .shadow(color: .black.opacity(isHovered ? 0.25 : 0), radius: 20, y: 15)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .opacity(isAppeared ? 1 : 0)
        .onAppear {
            let delay = Double.random(in: 0...0.2)
            withAnimation(.smooth(duration: 0.4).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var logoContent: some View {
        ZStack {
            if let logo = node.logoPath {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(logo)")) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView().controlSize(.small)
                }
                .frame(width: 100, height: 45)
                .scaleEffect(isHovered ? 0.6 : 1.0)
                .opacity(isHovered ? 0.1 : 1.0)
                .blur(radius: isHovered ? 5 : 0)
            }
            
            VStack(spacing: 2) {
                Text(node.name)
                    .font(.system(size: 15, weight: .black))
                    .multilineTextAlignment(.center)
                Text("\(node.count) TITLES")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(appAccent.color)
            }
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1.0 : 0.7)
            .offset(y: isHovered ? 0 : 20)
        }
    }
    
    @ViewBuilder
    private var textContent: some View {
        VStack(spacing: 4) {
            Text(node.name.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .kerning(1.2)
                .offset(y: isHovered ? -8 : 10)
            
            Text("\(node.count) ITEMS")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(appAccent.color)
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? -8 : 10)
        }
    }
}
