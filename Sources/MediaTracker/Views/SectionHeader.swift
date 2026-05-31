import SwiftUI

struct SectionHeader: View {
    let title: String
    let icon: String?
    let iconColor: Color
    var subtitle: String? = nil
    var scrollProgress: Double? = nil
    var showDivider: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 24, weight: .semibold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Font.title)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AppTheme.Font.bodyBold)
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
                                .frame(height: AppTheme.Spacing.micro)
                            
                            Capsule()
                                .fill(AppTheme.Colors.accent.gradient)
                                .frame(width: itemWidth, height: AppTheme.Spacing.micro)
                                .offset(x: progress * scrollableTrackWidth)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: 150, height: AppTheme.Spacing.micro)
                    .padding(.trailing, AppTheme.Spacing.small)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
            
            if showDivider {
                Divider()
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.top, AppTheme.Spacing.micro)
            }
        }
    }
}

#Preview("Section Header") {
    VStack(spacing: 20) {
        SectionHeader(title: "Top Genres", icon: "sparkles", iconColor: .indigo)
        SectionHeader(title: "Coming Soon", icon: "calendar", iconColor: .orange, subtitle: "Next 30 Days")
        SectionHeader(title: "Continue Watching", icon: nil, iconColor: .blue, scrollProgress: 0.3)
    }
    .padding()
}
