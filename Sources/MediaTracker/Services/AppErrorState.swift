import SwiftUI
import Observation

@MainActor
@Observable
class AppErrorState {
    static let shared = AppErrorState()
    
    var currentToast: Toast?
    var isImporting = false
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: ToastStyle
        let duration: Double
        
        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    enum ToastStyle {
        case info
        case success
        case warning
        case error
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
    
    func showToast(_ message: String, style: ToastStyle = .info, duration: Double = 3.5) {
        let toast = Toast(message: message, style: style, duration: duration)
        dismissTask?.cancel()
        
        withAnimation(AppTheme.Animation.springGentle) {
            currentToast = toast
        }
        
        let toastID = toast.id
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self.currentToast?.id == toastID else { return }
            
            withAnimation(AppTheme.Animation.springGentle) {
                self.currentToast = nil
            }
        }
    }
    
    func surfaceError(_ message: String) {
        showToast(message, style: .error)
    }
    
    func handleError(_ error: Error, message: String? = nil) {
        let finalMessage = message ?? error.localizedDescription
        surfaceError(finalMessage)
        AppLogger.error("Error caught: \(error)")
    }
}

extension View {
    func appErrorToast(state: AppErrorState) -> some View {
        ZStack {
            self
            
            VStack {
                Spacer()
                if let toast = state.currentToast {
                    ToastView(toast: toast)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(1000)
        }
    }
}

struct ToastView: View {
    let toast: AppErrorState.Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.color)
                .font(.system(size: 18, weight: .bold))
            
            Text(toast.message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .overlay {
            Capsule()
                .stroke(toast.style.color.opacity(0.2), lineWidth: 0.5)
        }
    }
}
