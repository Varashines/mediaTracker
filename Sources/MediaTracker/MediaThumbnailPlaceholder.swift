import SwiftUI

struct MediaThumbnailPlaceholder: View {
    let mode: MediaThumbnailView.DisplayMode
    @Environment(\.colorScheme) var colorScheme
    
    private var width: CGFloat {
        switch mode {
        case .hero: return 200
        default: return 160
        }
    }

    private var height: CGFloat {
        switch mode {
        case .hero: return 300
        default: return 240
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: mode == .hero ? 16 : 12)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.2 : 0.15))
                .overlay {
                    RoundedRectangle(cornerRadius: mode == .hero ? 16 : 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                }
            
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: width, height: height)
    }
}
