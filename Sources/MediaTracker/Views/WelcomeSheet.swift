import SwiftUI

struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("has_seen_welcome") private var hasSeenWelcome = false
    var onImportBackup: (() -> Void)? = nil
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showDescription = false
    @State private var showButtons = false
    @State private var isPrimaryHovered = false
    @State private var isSecondaryHovered = false
    @State private var isEmptyHovered = false
    @State private var isImportHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, AppTheme.Spacing.medium)
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
                .padding(.bottom, AppTheme.Spacing.large)
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 8)

            Text("Track every movie and TV show you watch.\nGet personalized recommendations and never miss an episode.")
                .font(AppTheme.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.bottom, AppTheme.Spacing.xLarge)
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
                    .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .buttonStyle(.plain)
                .scaleEffect(isPrimaryHovered ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isPrimaryHovered ? 0.15 : 0), radius: 8, y: isPrimaryHovered ? 4 : 0)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.springSnappy) { isPrimaryHovered = hovering }
                }
                .accessibilityLabel("Get Free TMDB API Key")

                Button {
                    hasSeenWelcome = true
                    dismiss()
                } label: {
                    Text("I already have a key")
                        .font(AppTheme.Font.bodyMedium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(isSecondaryHovered ? AppTheme.Colors.accent.opacity(0.08) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .buttonStyle(.plain)
                .scaleEffect(isSecondaryHovered ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.springSnappy) { isSecondaryHovered = hovering }
                }
                .accessibilityLabel("I already have a key")

                Button {
                    hasSeenWelcome = true
                    dismiss()
                    onImportBackup?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(AppTheme.Font.caption)
                        Text("Import from Backup")
                            .font(AppTheme.Font.body)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .fill(isImportHovered ? AppTheme.Colors.accent.opacity(0.08) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .buttonStyle(.plain)
                .scaleEffect(isImportHovered ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.springSnappy) { isImportHovered = hovering }
                }
                .accessibilityLabel("Import from Backup")

                Button {
                    hasSeenWelcome = true
                    dismiss()
                } label: {
                    Text("Start with empty library")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                .fill(isEmptyHovered ? AppTheme.Colors.surfaceGhost(for: colorScheme) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                }
                .buttonStyle(.plain)
                .scaleEffect(isEmptyHovered ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.springSnappy) { isEmptyHovered = hovering }
                }
                .accessibilityLabel("Start with empty library")
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
        .background(AppTheme.Colors.surface(for: colorScheme))
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
