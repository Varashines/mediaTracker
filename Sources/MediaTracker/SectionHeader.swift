import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String?
    let iconColor: Color
    var subtitle: String? = nil
    var scrollProgress: Double? = nil
    var showDivider: Bool = false
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 24, weight: .black))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(1.0)
                    }
                }
                
                Spacer()
                
                if let progress = scrollProgress {
                    GeometryReader { geo in
                        let availableWidth = geo.size.width
                        let itemWidth = max(40, min(availableWidth, availableWidth * 0.3))
                        let scrollableTrackWidth = availableWidth - itemWidth
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(appAccent.color.gradient)
                                .frame(width: itemWidth, height: 4)
                                .offset(x: progress * scrollableTrackWidth)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: 150, height: 4)
                    .padding(.trailing, 10)
                }
            }
            .padding(.horizontal, 40)
            
            if showDivider {
                Divider().padding(.horizontal, 40).padding(.top, 4)
            }
        }
    }
}
