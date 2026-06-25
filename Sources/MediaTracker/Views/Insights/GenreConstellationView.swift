import SwiftUI

struct GenreConstellationView: View {
    let items: [(name: String, percentage: Double)]

    var body: some View {
        if items.isEmpty {
            CuteEmptyState(icon: "sparkles.magnifyingglass", message: "Discover more genres!", color: .indigo)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: AppTheme.Spacing.large)], spacing: AppTheme.Spacing.large) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.name) { idx, item in
                    GenreCard(rank: idx + 1, name: item.name, percentage: item.percentage)
                        .modifier(StaggerModifier(index: idx))
                }
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)
        }
    }
}

private struct GenreCard: View {
    let rank: Int
    let name: String
    let percentage: Double
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Default: genre name only
            VStack(spacing: 6) {
                Text(name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .opacity(isHovered ? 0 : 1)
            .scaleEffect(isHovered ? 0.95 : 1.0)

            // Hover: genre name + percentage
            VStack(spacing: 6) {
                Text(name)
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(String(format: "%.0f", percentage * 100))%")
                    .font(AppTheme.Font.monoCaption)
                    .foregroundStyle(.indigo)
            }
            .opacity(isHovered ? 1 : 0)
            .offset(y: isHovered ? 0 : 8)

            Text("\(rank)")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .foregroundStyle(.indigo.opacity(isHovered ? 0.22 : 0.10))
                .offset(x: -10, y: -6)
                .allowsHitTesting(false)
        }
        .padding(.vertical, AppTheme.Spacing.medium)
        .padding(.horizontal, AppTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isHovered ? Color.indigo.opacity(colorScheme == .dark ? 0.06 : 0.03) : .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: isHovered ? 4 : 0)
        .animation(AppTheme.Animation.springSnappy, value: isHovered)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.springSnappy) {
                isHovered = hovering
            }
        }
    }
}

private struct StaggerModifier: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .onAppear {
                if !hasAppeared {
                    withAnimation(AppTheme.Animation.springGentle.delay(Double(index % 6) * 0.05)) {
                        hasAppeared = true
                    }
                }
            }
    }
}
