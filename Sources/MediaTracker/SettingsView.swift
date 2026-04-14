import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    
    var body: some View {
        TabView {
            GeneralSettingsTab(allItems: allItems, modelContext: modelContext)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsTab: View {
    let allItems: [MediaItem]
    let modelContext: ModelContext
    
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("google_books_api_key") private var googleBooksApiKey = ""
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("TMDB Key", text: $tmdbApiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get TMDB Key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Google Books Key", text: $googleBooksApiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get Google Cloud Key", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            } header: {
                Text("API Configuration")
                    .font(.headline)
            }
            .padding(.bottom, 10)
            
            Section {
                HStack(spacing: 20) {
                    Button(action: {
                        DataService.shared.exportLibrary(items: allItems)
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: {
                        DataService.shared.importLibrary(modelContext: modelContext)
                    }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                .padding(.vertical, 8)
                Text("Back up your library or restore it on another Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Data Management")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

struct AdvancedSettingsTab: View {
    var body: some View {
        Form {
            Section {
                Button("Send Test Notification") {
                    NotificationManager.shared.sendTestNotification()
                }
            } header: {
                Text("Diagnostics")
                    .font(.headline)
            }
            .padding(.bottom, 10)
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MediaTracker v2.0")
                        .font(.headline)
                    Text("Data provided by TMDB, TVMaze, and Google Books.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
