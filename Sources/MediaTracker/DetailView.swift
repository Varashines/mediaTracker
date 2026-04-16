import SwiftUI
import SwiftData

struct DetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var viewModel: DetailViewModel
    
    init(item: MediaItem) {
        _viewModel = State(initialValue: DetailViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Liquid Glass Foundation Background
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                viewModel.themeColor
                    .opacity(colorScheme == .dark ? 0.35 : 0.15)
                    .blur(radius: 120)
                    .ignoresSafeArea()
                
                LinearGradient(
                    gradient: Gradient(colors: [viewModel.themeColor.opacity(colorScheme == .dark ? 0.25 : 0.1), .clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .animation(.easeInOut(duration: 0.8), value: viewModel.themeColor)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Optimized Header Section
                    MediaHeaderView(item: viewModel.item, themeColor: viewModel.themeColor, nextEpisodeText: viewModel.nextText) { newState in
                        if newState == .completed {
                            viewModel.markAllAsWatched()
                        }
                    }
                    .onAppear {
                        viewModel.updateThemeColor()
                    }
                    
                    if (viewModel.item.type == .movie && viewModel.item.movieDetails?.genres.isEmpty != false) || (viewModel.item.type == .tvShow && viewModel.item.tvShowDetails?.status == nil) {
                        if !APIClient.shared.isTMDBConfigured {
                            Text("Please add your TMDB API Key in Settings to see more details.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let cast = (viewModel.item.movieDetails?.cast ?? viewModel.item.tvShowDetails?.cast), !cast.isEmpty {
                        Divider()
                        CastSectionViewNew(cast: cast, themeColor: viewModel.themeColor)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    if let tv = viewModel.item.tvShowDetails {
                        Divider()
                        TVTrackingView(tvDetails: tv, themeColor: viewModel.themeColor, onWatchedToggle: {
                            viewModel.checkOverallCompletion()
                        })
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    Divider()
                    
                    RatingSection(item: viewModel.item)
                        .transition(.opacity)
                }
                .padding(30)
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
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
                }
            }
            .onAppear {
                viewModel.refreshData()
            }
            .tint(viewModel.themeColor)
        }
    }
}
