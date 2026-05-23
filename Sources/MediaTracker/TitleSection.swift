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
            VStack(alignment: .leading, spacing: 18) {
                // 1. Editorial Title & Creators
                VStack(alignment: .leading, spacing: 8) {
                    let titleView = Text(item.title)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.primary)
                    
                    if let ns = namespace {
                        titleView.matchedGeometryEffect(id: "title_\(item.id)", in: ns)
                    } else {
                        titleView
                    }
                    
                    let creators = item.cachedCreators
                    if !creators.isEmpty {
                        Text("\(item.type == .movie ? "Directed by" : "Created by") \(creators.joined(separator: ", "))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // 2. Metadata Badges
                HStack(spacing: 12) {
                    let accent = themeColor.highContrastAccent(colorScheme: colorScheme)
                    let bgAccent = themeColor.luminousAccent(colorScheme: colorScheme)
                    
                    Text(item.type?.rawValue.uppercased() ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(accent)
                        .background {
                            Capsule()
                                .fill(bgAccent.opacity(colorScheme == .dark ? 0.2 : 0.4))
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(accent.opacity(0.1), lineWidth: 0.5)
                        }

                    if item.isUpcoming, let dateText = item.detailBadgeText {
                        let isStreaming = (item.cachedNextAiringDate ?? Date()) < Date()
                        let color = isStreaming ? Color.green : Color.orange
                        HStack(spacing: 4) {
                            Image(systemName: isStreaming ? "play.fill" : "calendar")
                                .font(.system(size: 8, weight: .bold))
                            Text(dateText.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(1.2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(color)
                        .background {
                            Capsule()
                                .fill(color.opacity(0.15))
                        }
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(color.opacity(0.15), lineWidth: 0.5)
                        }
                    }
                }
                
                // 3. Unified Glass Action Bar
                HStack(spacing: 20) {
                    StatusPicker(item: item, onChange: onStatusChange)
                    
                    Divider().frame(height: 24).opacity(0.3)
                    
                    TasteToggle(item: item, themeColor: themeColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            }
        }
    }
}
