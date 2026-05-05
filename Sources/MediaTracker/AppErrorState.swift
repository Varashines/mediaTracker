import SwiftUI
import Observation

@Observable @MainActor
class AppErrorState {
    static let shared = AppErrorState()
    
    var currentToast: ToastInfo?
    var showToast: Bool = false
    
    enum ToastType {
        case error, success, info
        
        var color: Color {
            switch self {
            case .error: return .red
            case .success: return .green
            case .info: return .blue
            }
        }
    }
    
    struct ToastInfo: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String
        let type: ToastType
    }
    
    func surfaceError(_ message: String, systemImage: String = "exclamationmark.triangle.fill") {
        showToast(message, systemImage: systemImage, type: .error)
    }
    
    func showToast(_ message: String, systemImage: String, type: ToastType = .info) {
        self.currentToast = ToastInfo(message: message, systemImage: systemImage, type: type)
        withAnimation(.smooth) {
            self.showToast = true
        }
        
        Task {
            // Auto-hide after 4 seconds
            try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
            await MainActor.run {
                withAnimation {
                    self.showToast = false
                }
            }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @Bindable var errorState: AppErrorState
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let toast = errorState.currentToast, errorState.showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: toast.systemImage)
                            .foregroundStyle(toast.type.color)
                        Text(toast.message)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea()
                .zIndex(100)
            }
        }
    }
}

extension View {
    func appErrorToast(state: AppErrorState) -> some View {
        self.modifier(ToastOverlay(errorState: state))
    }
}
