import SwiftUI
import SwiftData

struct TitleSection: View {
    @Bindable var item: MediaItem
    let themeColor: Color
    var onStatusChange: ((MediaState?) -> Void)?
    var namespace: Namespace.ID? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if item.modelContext != nil && !item.isDeleted {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    let titleView = Text(item.title)
                        .font(.system(size: 34, weight: .bold))
                    
                    if let ns = namespace {
                        titleView.matchedGeometryEffect(id: "title_\(item.id)", in: ns)
                    } else {
                        titleView
                    }
                    
                    // Creators/Directors Row
                    let creators = (item.movieDetails?.creators ?? item.tvShowDetails?.creators) ?? []
                    if !creators.isEmpty {
                        Text("\(item.type == .movie ? "Directed by" : "Created by") \(creators.joined(separator: ", "))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, -2)
                    }
                }

                HStack(spacing: 12) {
                    Text(item.type?.rawValue ?? "")
                        .font(.subheadline.weight(.semibold))
                        .liquidGlassPill(accentColor: themeColor)

                    if item.isUpcoming {
                        let isStreaming = (item.cachedNextAiringDate ?? Date()) < Date()
                        let badge = Text(isStreaming ? "Now Streaming" : "Upcoming")
                            .font(.subheadline.weight(.bold))
                            .liquidGlassPill(accentColor: isStreaming ? Color.semanticGreen(for: colorScheme) : .orange)
                        
                        if let ns = namespace {
                            badge.matchedGeometryEffect(id: "badge_\(item.id)", in: ns)
                        } else {
                            badge
                        }
                    }

                    Spacer().frame(width: 10)

                    StatusPicker(item: item, onChange: onStatusChange)
                }
                
                // New Expressive Taste Toggle
                TasteToggle(item: item, themeColor: themeColor)
                    .padding(.top, 4)
            }
        }
    }
}
