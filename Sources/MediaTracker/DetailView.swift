import SwiftUI
import SwiftData

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var viewModel: DetailViewModel
    @State private var isAppeared = false
    @State private var isDeleted = false
    
    var onSearchActor: ((String) -> Void)? = nil
    var namespace: Namespace.ID? = nil
    
    init(item: MediaItem, namespace: Namespace.ID? = nil, onSearchActor: ((String) -> Void)? = nil) {
        _viewModel = State(initialValue: DetailViewModel(item: item))
        self.onSearchActor = onSearchActor
        self.namespace = namespace
    }
    
    var body: some View {
        ZStack {
            if isDeleted || viewModel.item.modelContext == nil || viewModel.item.isDeleted {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            } else {
                // Liquid Glass Foundation Background
                ZStack {
                    if themeStyle == .brand {
                        appAccent.brandBackground(for: colorScheme)
                            .ignoresSafeArea()
                    } else {
                        Color(NSColor.windowBackgroundColor)
                            .ignoresSafeArea()
                    }
                    
                    viewModel.themeColor
                        .opacity(isAppeared ? (colorScheme == .dark ? 0.4 : 0.25) : 0)
                        .blur(radius: isAppeared ? 120 : 80)
                        .scaleEffect(isAppeared ? 1.1 : 0.9)
                        .ignoresSafeArea()
                    
                    LinearGradient(
                        gradient: Gradient(colors: [viewModel.themeColor.opacity(isAppeared ? (colorScheme == .dark ? 0.3 : 0.2) : 0), .clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                .animation(.spring(response: 0.8, dampingFraction: 0.85), value: isAppeared)
                .animation(.easeInOut(duration: 1.0), value: viewModel.themeColor)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Optimized Header Section
                        MediaHeaderView(item: viewModel.item, themeColor: viewModel.themeColor, namespace: namespace) { newState in
                            if newState == .completed {
                                viewModel.markAllAsWatched()
                            }
                        }
                        .onAppear {
                            viewModel.updateThemeColor()
                            viewModel.refreshData() 
                        }
                        
                        if (viewModel.item.type == .movie && viewModel.item.movieDetails?.genres.isEmpty != false) || (viewModel.item.type == .tvShow && viewModel.item.tvShowDetails?.status == nil) {
                            if !APIClient.shared.isTMDBConfigured {
                                Text("Please add your TMDB API Key in Settings to see more details.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if let cast = (viewModel.item.movieDetails?.cast ?? viewModel.item.tvShowDetails?.cast), !cast.isEmpty {
                                Divider()
                                CastSectionViewNew(cast: cast, themeColor: viewModel.themeColor) { actorName in
                                    onSearchActor?(actorName)
                                }
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            
                            if let tv = viewModel.item.tvShowDetails {
                                Divider()
                                TVTrackingView(tvDetails: tv, themeColor: viewModel.themeColor, onWatchedToggle: {
                                    viewModel.checkOverallCompletion()
                                }, onSeasonSelected: { _ in
                                    viewModel.refreshData(force: true)
                                })
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            
                            Divider()
                        }
                    }
                    .padding(24)
                }
                .navigationTitle("Details")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 16) {
                            Button {
                                viewModel.refreshData(force: true)
                            } label: {
                                if viewModel.isRefreshing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(viewModel.isRefreshing)
                            
                            Button(role: .destructive) {
                                deleteItem()
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .onAppear {
                    viewModel.refreshData()
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.1)) {
                        isAppeared = true
                    }
                }
                .onDisappear {
                    isAppeared = false
                }
                .tint(viewModel.themeColor)
                .appBackground(tint: viewModel.themeColor, disableBrandBackground: true)
            }
        }
    }
    
    private func deleteItem() {
        let itemToDelete = viewModel.item
        let itemID = itemToDelete.id
        let itemType = itemToDelete.type ?? .movie
        let network = itemToDelete.cachedNetwork
        let genres = itemToDelete.cachedGenres
        let lang = itemToDelete.cachedLanguage
        let container = modelContext.container

        withAnimation {
            isDeleted = true
        }

        dismiss()

        // Use a slightly longer delay to ensure dismissal completes before deletion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationManager.shared.cancelNotification(id: itemID, type: itemType)
            modelContext.delete(itemToDelete)
            try? modelContext.save()

            Task.detached {
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.updateItemDeleted(network: network, genres: genres, language: lang)
            }
        }
    }}
