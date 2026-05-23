import SwiftUI

struct CollaborationsLedgerView: View {
    let collaborations: [CreatorCollaboration]

    var body: some View {
        if !collaborations.isEmpty {
            DashboardCard {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Row
                    HStack {
                        Text("ACTOR")
                            .font(AppTheme.Font.smallBold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("DIRECTOR / CREATOR")
                            .font(AppTheme.Font.smallBold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("COLLABORATIONS")
                            .font(AppTheme.Font.smallBold)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.bottom, AppTheme.Spacing.tiny)
                    
                    Divider()
                        .padding(.bottom, AppTheme.Spacing.tiny)

                    // Data Rows
                    ForEach(Array(collaborations.prefix(5).enumerated()), id: \.element.id) { index, col in
                        HStack {
                            Text(col.actorName)
                                .font(AppTheme.Font.bodyBold)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(col.creatorName)
                                .font(AppTheme.Font.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(col.count) \(col.count == 1 ? "title" : "titles")")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, AppTheme.Spacing.tiny)
                        
                        if index < min(collaborations.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
