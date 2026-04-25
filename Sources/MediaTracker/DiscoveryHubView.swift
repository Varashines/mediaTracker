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
        
        let syncService = DiscoverySyncService(modelContainer: container)

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            // Local Aggregation only - no networking here
            await syncService.syncLibrary(force: force)
            
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
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(appAccent.color)
                
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 40)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: style == .logo ? 200 : 180), spacing: 24)], spacing: 24) {
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

    private var themeColor: Color {
        if let hex = node.themeColorHex, let color = Color(hex: hex) {
            return color
        }
        return appAccent.color
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Main Layer
                Group {
                    if style == .logo {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(themeColor.opacity(isHovered ? 0.6 : 0.15), lineWidth: isHovered ? 2 : 1)
                            }
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .overlay {
                                Capsule()
                                    .stroke(themeColor.opacity(isHovered ? 0.6 : 0.15), lineWidth: isHovered ? 2 : 1)
                            }
                    }
                }
                .shadow(color: themeColor.opacity(isHovered ? 0.2 : 0), radius: isHovered ? 15 : 0, y: isHovered ? 8 : 0)
                
                if style == .logo {
                    logoContent
                } else {
                    textContent
                }
            }
            .frame(height: style == .logo ? 140 : 80)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .opacity(isAppeared ? 1 : 0)
        .onAppear {
            let delay = Double.random(in: 0...0.15)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                isAppeared = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
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
                .frame(width: isHovered ? 90 : 120, height: isHovered ? 45 : 60)
                .offset(y: isHovered ? -15 : 0)
            } else {
                Text(node.name)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .offset(y: isHovered ? -15 : 0)
            }
            
            VStack(spacing: 2) {
                if node.logoPath != nil {
                    Text(node.name)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                Text("\(node.count) TITLES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 30 : 45)
            .scaleEffect(isHovered ? 1.0 : 0.9)
        }
        .padding(20)
    }
    
    @ViewBuilder
    private var textContent: some View {
        ZStack {
            Text(node.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .offset(y: isHovered ? -8 : 0)
            
            Text("\(node.count) ITEMS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? 12 : 20)
        }
    }
}
