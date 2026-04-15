import SwiftUI
import SwiftData

struct DetailView: View {
    @State private var viewModel: DetailViewModel
    
    init(item: MediaItem) {
        _viewModel = State(initialValue: DetailViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Dynamic Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [viewModel.themeColor.opacity(0.15), Color(NSColor.windowBackgroundColor)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
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
                        CastSectionView(cast: cast)
                    }
                    
                    if let tv = viewModel.item.tvShowDetails {
                        Divider()
                        TVTrackingView(tvDetails: tv, onWatchedToggle: {
                            viewModel.checkOverallCompletion()
                        })
                    }
                    
                    Divider()
                    
                    RatingSection(item: viewModel.item)
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
