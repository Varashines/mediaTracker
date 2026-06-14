import SwiftUI

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("has_seen_welcome") private var hasSeenWelcome = false
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showDescription = false
    @State private var showButtons = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 16)
                    .scaleEffect(showIcon ? 1 : 0.5)
                    .opacity(showIcon ? 1 : 0)
            }

            Text("Welcome to")
                .font(AppTheme.Font.title3)
                .foregroundStyle(.secondary)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 8)

            Text("MediaTracker")
                .font(AppTheme.Font.titleLarge)
                .foregroundStyle(.primary)
                .padding(.bottom, 24)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 8)

            Text("Track every movie and TV show you watch.\nGet personalized recommendations and never miss an episode.")
                .font(AppTheme.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
                .opacity(showDescription ? 1 : 0)
                .offset(y: showDescription ? 0 : 8)

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
            .opacity(showButtons ? 1 : 0)
            .offset(y: showButtons ? 0 : 12)

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
        .onAppear {
            withAnimation(AppTheme.Animation.springGentle.delay(0.1)) { showIcon = true }
            withAnimation(AppTheme.Animation.springGentle.delay(0.25)) { showTitle = true }
            withAnimation(AppTheme.Animation.springGentle.delay(0.4)) { showDescription = true }
            withAnimation(AppTheme.Animation.springGentle.delay(0.55)) { showButtons = true }
        }
    }
}

#Preview {
    WelcomeSheet()
}
