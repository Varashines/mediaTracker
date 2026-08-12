import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @State private var service = AppLockService.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            AppTheme.Colors.background(for: colorScheme).ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.medium) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text("MediaTracker")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.primary)

                if AppLockService.biometricsAvailable {
                    Button {
                        attemptUnlock()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.mini) {
                            Image(systemName: "touchid")
                            Text("Unlock with Touch ID")
                        }
                        .font(AppTheme.Font.bodyBold)
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Touch ID unavailable — open Settings to disable the lock.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .onAppear { attemptUnlock() }
    }

    private func attemptUnlock() {
        Task {
            let ok = await service.requestBiometricUnlock()
            await MainActor.run {
                if ok { service.unlock() }
            }
        }
    }
}
