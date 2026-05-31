import SwiftUI

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("has_seen_welcome") private var hasSeenWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 16)
            }

            Text("Welcome to")
                .font(AppTheme.Font.title3)
                .foregroundStyle(.secondary)

            Text("MediaTracker")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.bottom, 24)

            Text("Track every movie and TV show you watch.\nGet personalized recommendations and never miss an episode.")
                .font(AppTheme.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.themoviedb.org/settings/api")!)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(AppTheme.Font.body)
                        Text("Get Free TMDB API Key")
                            .font(AppTheme.Font.bodyBold)
                        Image(systemName: "arrow.up.right")
                            .font(AppTheme.Font.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .buttonStyle(.plain)

                Button {
                    hasSeenWelcome = true
                    dismiss()
                } label: {
                    Text("I already have a key")
                        .font(AppTheme.Font.bodyMedium)
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    hasSeenWelcome = true
                    dismiss()
                } label: {
                    Text("Explore in Demo Mode")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("You can always set this up later in Settings → Connect")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 24)
        }
        .frame(width: 380, height: 520)
        .background(AppTheme.Colors.background(for: colorScheme))
        .background {
            Button("") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
                .opacity(0)
        }
    }
}

#Preview {
    WelcomeSheet()
}
