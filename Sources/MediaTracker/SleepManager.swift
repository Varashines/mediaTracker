import SwiftUI
import Combine

@MainActor
@Observable
class SleepManager {
    static let shared = SleepManager()
    
    var isAsleep: Bool = false
    var purgeDataCache: (() -> Void)?
    private var timer: AnyCancellable?
    private let idleThreshold: TimeInterval = 120 // 2 minutes
    
    private init() {
        resetTimer()
        setupInteractionMonitor()
    }
    
    func resetTimer() {
        if isAsleep {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isAsleep = false
            }
        }
        
        timer?.cancel()
        timer = Timer.publish(every: idleThreshold, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.enterSleepMode()
            }
    }
    
    private func enterSleepMode() {
        guard !isAsleep else { return }
        withAnimation(.easeInOut(duration: 1.0)) {
            isAsleep = true
        }
        purgeCaches()
        purgeDataCache?()
        print("💤 App entered sleep mode due to inactivity. Caches and Context purged.")
    }
    
    private func purgeCaches() {
        // 1. Clear URLCache (Networking)
        URLCache.shared.removeAllCachedResponses()
        
        // 2. Clear ImageCache (Memory part)
        ImageCache.shared.clearMemoryCache()
    }
    
    private func setupInteractionMonitor() {
        #if os(macOS)
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .mouseMoved, .scrollWheel]) { [weak self] event in
            self?.resetTimer()
            return event
        }
        #endif
    }
}

struct SleepOverlayModifier: ViewModifier {
    @Bindable var sleepManager = SleepManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(sleepManager.isAsleep)
                .blur(radius: sleepManager.isAsleep ? 10 : 0)
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
