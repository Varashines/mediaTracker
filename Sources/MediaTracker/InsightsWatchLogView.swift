import SwiftUI

struct WatchLogTimelineView: View {
    let completedItems: [CompletedItemRepresentation]

    var body: some View {
        DashboardCard {
            if completedItems.isEmpty {
                HStack {
                    Spacer()
                    Text("No watch history records")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 80)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completedItems.prefix(15).enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                if index < min(completedItems.count, 15) - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: 1)
                                }
                            }
                            .frame(width: 12)

                            Text(formatDate(item.completedDate))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(AppTheme.Font.bodyBold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(item.typeValue.uppercased())
                                    .font(AppTheme.Font.tiny)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }

                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date).uppercased()
    }
}
