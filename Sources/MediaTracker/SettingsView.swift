import SwiftUI

struct SettingsView: View {
    @AppStorage("tmdb_api_key") private var tmdbApiKey = ""
    @AppStorage("google_books_api_key") private var googleBooksApiKey = ""
    
    var body: some View {
        Form {
            Section("API Keys") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TMDB API Key")
                        .font(.headline)
                    TextField("Enter TMDB Key", text: $tmdbApiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get TMDB Key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.caption)
                }
                .padding(.vertical, 5)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Google Books API Key (Optional)")
                        .font(.headline)
                    TextField("Enter Google Books Key", text: $googleBooksApiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get Google Cloud Key", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                        .font(.caption)
                }
                .padding(.vertical, 5)
            }
            
            Section("Notifications") {
                Button("Send Test Notification") {
                    NotificationManager.shared.sendTestNotification()
                }
            }
            
            Section("About") {
                Text("MediaTracker v1.0")
                Text("Data provided by TMDB, TVMaze, and Google Books.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}
