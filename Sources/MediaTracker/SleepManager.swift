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
            print("🕒 App became idle. Background tasks prioritized.")
        } else if isIdle && timeSinceInteraction < idleThreshold {
            isIdle = false
        }

        // 2. Handle "Sleep" (Untouched for 120s, locks UI)
        let preventSleep = UserDefaults.standard.bool(forKey: "prevent_sleep_mode")
        guard !isAsleep && !preventSleep else { return }
        
        if timeSinceInteraction >= sleepThreshold {
            enterSleepMode()
        }
    }
    
    func resetTimer() {
        lastInteractionDate = Date()
        if isIdle { isIdle = false }
        if isAsleep {
            withAnimation(.smooth) {
                isAsleep = false
            }
            print("🌅 App woke up from sleep mode.")
        }
    }
    
    func forceSleep() {
        enterSleepMode()
    }
    
    private func enterSleepMode() {
        guard !isAsleep else { return }
        withAnimation(.easeInOut(duration: 1.0)) {
            isAsleep = true
        }
        // Phase 4 Optimization: Removed aggressive manual cache purging.
        // We now trust NSCache's native response to system memory pressure warnings.
        purgeDataCache?()
        print("💤 App entered sleep mode due to inactivity. UI interactions throttled.")
    }
    
    private func setupInteractionMonitor() {
        #if os(macOS)
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved, .scrollWheel]) { [weak self] event in
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
                    .background(.ultraThinMaterial)
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
