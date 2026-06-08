import SwiftUI
import Combine

@MainActor
@Observable
class SleepManager {
    static let shared = SleepManager()
    
    var isAsleep: Bool = false
    var isIdle: Bool = false
    var purgeDataCache: (() -> Void)?
    private var lastInteractionDate: Date = Date()
    private var timer: AnyCancellable?
    private let sleepThreshold: TimeInterval = 120 // 2 minutes
    private let idleThreshold: TimeInterval = 60 // 1 minute for silent syncs
    
    private init() {
        setupInteractionMonitor()
        startIdleTimer()
    }
    
    private func startIdleTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 5, on: .main, in: .common) // Increased frequency for more precise idle detection
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkIdleState()
            }
    }

    private func checkIdleState() {
        let now = Date()
        let timeSinceInteraction = now.timeIntervalSince(lastInteractionDate)

        // 1. Handle "Idle" (Untouched for 60s, good for background syncs)
        if !isIdle && timeSinceInteraction >= idleThreshold {
            isIdle = true
            AppLogger.info("🕒 App became idle. Background tasks prioritized.", logger: AppLogger.background)
            BackgroundTaskManager.shared.handleIdleStateChange(isIdle: true)
        } else if isIdle && timeSinceInteraction < idleThreshold {
            isIdle = false
            BackgroundTaskManager.shared.handleIdleStateChange(isIdle: false)
        }

        // 2. Handle "Sleep" (Untouched for 120s, locks UI)
        let preventSleep = UserDefaults.standard.bool(forKey: UserDefaultsKeys.preventSleepMode.rawValue)
        guard !isAsleep && !preventSleep else { return }
        
        if timeSinceInteraction >= sleepThreshold {
            enterSleepMode()
        }
    }
    
    func resetTimer() {
        lastInteractionDate = Date()
        if isIdle { isIdle = false }
        if isAsleep {
            withAnimation(.easeInOut(duration: 0.4)) {
                isAsleep = false
            }
            // Restart timer after waking from sleep
            startIdleTimer()
            AppLogger.info("🌅 App woke up from sleep mode.", logger: AppLogger.background)
        }
    }
    
    func forceSleep() {
        enterSleepMode()
    }
    
    private func enterSleepMode() {
        guard !isAsleep else { return }
        withAnimation(.easeIn(duration: 0.6)) {
            isAsleep = true
        }
        // Stop polling timer — no need to check idle state while asleep
        timer?.cancel()
        timer = nil
        purgeDataCache?()
        AppLogger.info("💤 App entered sleep mode due to inactivity. UI interactions throttled.", logger: AppLogger.background)
    }
    
    private var eventMonitor: Any?
    
    private func setupInteractionMonitor() {
        #if os(macOS)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            // ONLY wake up if the user is interacting with the main window.
            // This allows the MenuBar dashboard to be used without waking the heavy main app view.
            guard let self = self, let main = NSApp.mainWindow, event.window == main else {
                return event
            }
            
            self.resetTimer()
            return event
        }
        #endif
    }
}

// Phase 4: Environment Injection for Decoupling
private struct SleepManagerKey: EnvironmentKey {
    static var defaultValue: SleepManager {
        MainActor.assumeIsolated { SleepManager.shared }
    }
}

extension EnvironmentValues {
    var sleepManager: SleepManager {
        get { self[SleepManagerKey.self] }
        set { self[SleepManagerKey.self] = newValue }
    }
}

struct SleepOverlayModifier: ViewModifier {
    @Environment(\.sleepManager) var sleepManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(sleepManager.isAsleep)
                .opacity(sleepManager.isAsleep ? 0 : 1)
                .scaleEffect(sleepManager.isAsleep ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.6), value: sleepManager.isAsleep)
            
            if sleepManager.isAsleep {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("App is in Sleep Mode")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                        
                        Text("Click or press any key to wake up")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(40)
                    .background {
                        RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                }
                .transition(.opacity)
                .onTapGesture {
                    sleepManager.resetTimer()
                }
            }
        }
    }
}

extension View {
    func sleepModeSupport() -> some View {
        self.modifier(SleepOverlayModifier())
    }
}
