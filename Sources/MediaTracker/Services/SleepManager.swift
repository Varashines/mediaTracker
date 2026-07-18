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
    private var idleWorkItem: DispatchWorkItem?
    private var sleepWorkItem: DispatchWorkItem?
    private let sleepThreshold: TimeInterval = 120 // 2 minutes
    private let idleThreshold: TimeInterval = 60 // 1 minute for silent syncs
    
    private init() {
        setupInteractionMonitor()
        scheduleIdleCheck()
    }
    
    private func scheduleIdleCheck() {
        idleWorkItem?.cancel()
        sleepWorkItem?.cancel()
        
        let idleItem = DispatchWorkItem { [weak self] in
            self?.checkIdleState()
        }
        let sleepItem = DispatchWorkItem { [weak self] in
            self?.checkIdleState()
        }
        
        idleWorkItem = idleItem
        sleepWorkItem = sleepItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + idleThreshold, execute: idleItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + sleepThreshold, execute: sleepItem)
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
            // Reschedule idle/sleep checks
            scheduleIdleCheck()
            updateWindowChrome()
            AppLogger.info("🌅 App woke up from sleep mode.", logger: AppLogger.background)
        } else {
            // Reschedule the timers since interaction occurred
            scheduleIdleCheck()
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
        // Cancel pending checks — no need while asleep
        idleWorkItem?.cancel()
        sleepWorkItem?.cancel()
        purgeDataCache?()
        updateWindowChrome()
        AppLogger.info("💤 App entered sleep mode due to inactivity. UI interactions throttled.", logger: AppLogger.background)
    }
    
    private var eventMonitor: Any?
    private let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .mouseMoved, .scrollWheel]

    private func setupInteractionMonitor() {
        #if os(macOS)
        // macOS does not deliver .mouseMoved events unless the window explicitly opts in.
        // Observe the main window so we can enable it as soon as it appears.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.enableMouseMoveTracking()
            }
        }
        // Fire once in case the main window already exists (e.g. app restored state).
        Task { @MainActor [weak self] in
            self?.enableMouseMoveTracking()
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self = self, let main = NSApp?.mainWindow, event.window == main else {
                return event
            }

            let now = Date()

            // Debounce mouse-move to 1 Hz — it fires at display refresh rate (60-120 Hz).
            // Without debouncing, DispatchWorkItem is cancelled/recreated 60+ times/sec.
            if event.type == .mouseMoved {
                let elapsed = now.timeIntervalSince(self.lastInteractionDate)
                // Wake immediately if asleep; otherwise throttle to avoid busywork
                if !self.isAsleep && elapsed < 1.0 {
                    return event
                }
            }

            self.lastInteractionDate = now
            self.resetTimer()
            return event
        }
        #endif
    }

    private func enableMouseMoveTracking() {
        #if os(macOS)
        guard let window = NSApp?.mainWindow else { return }
        window.acceptsMouseMovedEvents = true
        #endif
    }

    @MainActor
    private func updateWindowChrome() {
        #if os(macOS)
        guard let window = NSApp?.mainWindow else { return }
        if isAsleep {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar?.isVisible = false
        } else {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.toolbar?.isVisible = true
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(sleepManager.isAsleep)
                .opacity(sleepManager.isAsleep ? 0 : 1)
                .scaleEffect(sleepManager.isAsleep ? 0.98 : 1.0)
                .animation(AppTheme.Animation.sleepTransition, value: sleepManager.isAsleep)

            if sleepManager.isAsleep {
                ZStack {
                    Color.black.opacity(0.3)

                    VStack(spacing: 20) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("App is in Sleep Mode")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)

                        Text("Move your mouse, click, or press any key to wake up")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(40)
                    .background {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(AppThemeCoordinator.isReducingVisualEffects
                                ? AnyShapeStyle(AppTheme.Colors.background(for: colorScheme))
                                : AnyShapeStyle(.ultraThinMaterial))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func sleepModeSupport() -> some View {
        self.modifier(SleepOverlayModifier())
    }
}
