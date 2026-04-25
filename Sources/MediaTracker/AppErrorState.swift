import SwiftUI
import Observation

@Observable @MainActor
class AppErrorState {
    static let shared = AppErrorState()
    
    var currentError: AppError?
    var showToast: Bool = false
    
    struct AppError: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String
    }
    
    func surfaceError(_ message: String, systemImage: String = "exclamationmark.triangle.fill") {
        self.currentError = AppError(message: message, systemImage: systemImage)
        withAnimation {
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
            
            if let error = errorState.currentError, errorState.showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: error.systemImage)
                            .foregroundStyle(.red)
                        Text(error.message)
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
