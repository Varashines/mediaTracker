import SwiftUI

/// Reusable skeleton shown while a `DetailView` is loading its heavy content
/// (TV tracking, cast, recommendations). Mirrors the layout that will appear
/// once data arrives so the transition is smooth.
struct DetailSkeletonView: View {
    var needsTV: Bool = false
    var hasCast: Bool = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            if needsTV {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                    .fill(Color.primary.opacity(0.04))
                    .frame(height: 180)
            }
            if hasCast {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                    .fill(Color.primary.opacity(0.04))
                    .frame(height: 140)
            }
        }
        .shimmering()
    }
}
