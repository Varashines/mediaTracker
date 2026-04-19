import SwiftUI
import SwiftData

struct DetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme_style") private var themeStyle: ThemeStyle = .standard
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo
    
    @State private var viewModel: DetailViewModel
    @State private var isAppeared = false
    
    var onSearchActor: ((String) -> Void)? = nil
    var namespace: Namespace.ID? = nil
    
    init(item: MediaItem, namespace: Namespace.ID? = nil, onSearchActor: ((String) -> Void)? = nil) {
        _viewModel = State(initialValue: DetailViewModel(item: item))
        self.onSearchActor = onSearchActor
        self.namespace = namespace
    }
    
    var body: some View {
        ZStack {
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
                    .opacity(isAppeared ? (colorScheme == .dark ? 0.5 : 0.35) : 0)
                    .blur(radius: isAppeared ? 140 : 100)
                    .scaleEffect(isAppeared ? 1.2 : 0.8)
                    .ignoresSafeArea()
                
                LinearGradient(
                    gradient: Gradient(colors: [viewModel.themeColor.opacity(isAppeared ? (colorScheme == .dark ? 0.4 : 0.3) : 0), .clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .animation(.spring(response: 1.2, dampingFraction: 0.8), value: isAppeared)
            .animation(.easeInOut(duration: 0.8), value: viewModel.themeColor)
            
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
                            }, onSeasonSelected: { season in
                                Task {
                                    await viewModel.fetchEpisodesForSeason(season, tmdbID: tv.tmdbID)
                                }
                            })
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        
                        Divider()
                        
                        RatingSection(item: viewModel.item)
                            .transition(.opacity)
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
            .onChange(of: viewModel.item.lastStateChangeDate) {
                // Sync labels
            }
            .tint(viewModel.themeColor)
            .appBackground(tint: viewModel.themeColor, disableBrandBackground: true)
        }
    }
    
    private func deleteItem() {
        let itemToDelete = viewModel.item
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationManager.shared.cancelNotification(for: itemToDelete)
            modelContext.delete(itemToDelete)
            try? modelContext.save()
        }
    }
}
