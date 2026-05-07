import SwiftUI
import SwiftData

struct TitleSection: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    var onStatusChange: ((MediaState?) -> Void)?
    var namespace: Namespace.ID? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    let titleView = Text(item.title)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    if let ns = namespace {
                        titleView.matchedGeometryEffect(id: "title_\(item.id)", in: ns)
                    } else {
                        titleView
                    }
                    
                    // Creators/Directors Row
                    let creators = item.cachedCreators
                    if !creators.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: item.type == .movie ? "film.fill" : "app.badge.checkmark.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(themeColor.highContrastAccent(colorScheme: colorScheme))
                            
                            Text("\(item.type == .movie ? "Directed by" : "Created by") \(creators.joined(separator: ", "))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }

                HStack(spacing: 12) {
                    let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
                    let bgAccent = themeColor.luminousAccent(colorScheme: colorScheme)
                    HStack(spacing: 6) {
                        Text(item.type?.rawValue.uppercased() ?? "")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(bgAccent.opacity(colorScheme == .dark ? 0.15 : 0.4))
                            .clipShape(Capsule())
                            .foregroundStyle(accent)

                        if item.isUpcoming, let dateText = item.detailBadgeText {
                            let isStreaming = (item.cachedNextAiringDate ?? Date()) < Date()
                            HStack(spacing: 4) {
                                Image(systemName: isStreaming ? "play.fill" : "calendar")
                                    .font(.system(size: 8, weight: .black))
                                Text(dateText.uppercased())
                                    .font(.system(size: 10, weight: .black))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isStreaming ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(isStreaming ? .green : .orange)
                        }
                    }

                    Divider().frame(height: 20)

                    StatusPicker(item: item, onChange: onStatusChange)
                }
                
                // New Expressive Taste Toggle
                TasteToggle(item: item, themeColor: themeColor)
                    .padding(.top, 4)
            }
        }
    }
}
