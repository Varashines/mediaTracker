import SwiftUI
import SwiftData

struct MenuBarDashboard: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.colorScheme) var colorScheme
    
    // 1. Fetch In-Progress items (top 3)
    @Query(filter: #Predicate<MediaItem> { $0.stateValue == "Active" && $0.typeValue == "TV Show" },
           sort: \MediaItem.lastInteractionDate, order: .reverse)
    private var inProgress: [MediaItem]
    
    // 2. Fetch Upcoming items (top 3)
    @Query(filter: #Predicate<MediaItem> { $0.storedIsUpcoming == true },
           sort: \MediaItem.cachedNextAiringDate, order: .forward)
    private var upcoming: [MediaItem]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("DASHBOARD")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Image(systemName: "play.tv.fill")
                    .foregroundStyle(appAccent.color.gradient)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Section 1: UP NEXT
                    dashboardSection(title: "Up Next", icon: "play.fill", color: .blue) {
                        if inProgress.isEmpty {
                            emptyState(message: "Nothing in progress")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(inProgress.prefix(3)) { item in
                                    DashboardRow(item: item, themeColor: appAccent.color)
                                }
                            }
                        }
                    }
                    
                    // Section 2: AIRING SOON
                    dashboardSection(title: "Airing Soon", icon: "calendar", color: .orange) {
                        if upcoming.isEmpty {
                            emptyState(message: "No upcoming releases")
                        } else {
                            VStack(spacing: 12) {
                                ForEach(upcoming.prefix(3)) { item in
                                    DashboardRow(item: item, themeColor: appAccent.color)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Interactive Footer
            HStack(spacing: 12) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    // If no windows are visible, show the main one
                    if NSApplication.shared.windows.filter({ $0.level == .normal && $0.isVisible }).isEmpty {
                        // This is a bit complex in SwiftUI without a window reference, 
                        // but normally activating the app brings the main window back.
                    }
                } label: {
                    Label("Library", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                Button {
                    // Surgical Hide: Only hide main windows, keep process (and Menu Bar) active
                    for window in NSApplication.shared.windows {
                        if window.level == .normal {
                            window.orderOut(nil)
                        }
                    }
                    SleepManager.shared.forceSleep()
                } label: {
                    Label("Hide & Sleep", systemImage: "moon.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(appAccent.color.opacity(0.1))
                        .foregroundStyle(appAccent.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 320, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private func dashboardSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .kerning(1.0)
            }
            .foregroundStyle(color)
            
            content()
        }
    }
    
    @ViewBuilder
    private func emptyState(message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct DashboardRow: View {
    let item: MediaItem
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Poster Thumb
            if let urlString = item.posterURL, let url = URL(string: urlString) {
                CachedImage(url: url, targetSize: CGSize(width: 80, height: 120)) { _ in } placeholder: {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 60)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                
                if let nextEp = item.storedNextEpisodeLabel {
                    Text(nextEp)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let date = item.releaseDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                if item.storedIsBingeDrop {
                    Text("BINGE DROP")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
