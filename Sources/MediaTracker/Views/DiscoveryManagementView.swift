import SwiftUI
import SwiftData

struct DiscoveryManagementView: View {
    @Query(sort: \NetworkEntity.name) private var networkEntities: [NetworkEntity]
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var networkSearchText = ""
    @Environment(\.colorScheme) var colorScheme

    @State private var availableNetworks: [String] = []
    @State private var hiddenList: [String] = []
    @State private var addableNetworks: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Search and Add Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Search & Add Networks")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                
                TextField("Search all available networks...", text: $networkSearchText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                if !addableNetworks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(addableNetworks, id: \.self) { name in
                                Button {
                                    toggleHidden(name)
                                    FeedbackManager.shared.trigger(.click)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(name)
                                            .font(AppTheme.Font.label)
                                        Image(systemName: "plus.circle.fill")
                                            .font(AppTheme.Font.caption2)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.Colors.surfaceMuted(for: colorScheme))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: 44)
                } else if !networkSearchText.isEmpty {
                    Text("No matching networks found.")
                        .font(AppTheme.Font.label)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
            }
            
            Divider()

            // 2. Hidden Networks Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Hidden from Discovery")
                    .font(AppTheme.Font.bodyBold)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 0) {
                    if hiddenList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "eye.fill")
                                .font(AppTheme.Font.title2)
                            Text("All networks are currently visible.")
                                .font(AppTheme.Font.label)
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(hiddenList, id: \.self) { name in
                            HStack {
                                Text(name)
                                    .font(AppTheme.Font.settingsRowTitle)
                                Spacer()
                                Button { 
                                    toggleHidden(name) 
                                    FeedbackManager.shared.trigger(.click)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            if name != hiddenList.last {
                                Rectangle()
                                    .fill(AppTheme.Colors.strokeDefault(for: colorScheme))
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(AppTheme.Colors.surfaceGhost(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: networkEntities.count) { _, _ in recomputeLists() }
        .onChange(of: hiddenStudios) { _, _ in recomputeLists() }
        .onChange(of: networkSearchText) { _, _ in recomputeAddable() }
        .onAppear { recomputeLists() }
    }
    
    private func recomputeLists() {
        availableNetworks = networkEntities
            .filter { $0.count >= 4 }
            .map { $0.name }
            .sorted()
        
        let allHidden = hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }
        hiddenList = allHidden.filter { name in
            networkEntities.first(where: { $0.name == name })?.count ?? 0 >= 4
        }.sorted()
        
        recomputeAddable()
    }
    
    private func recomputeAddable() {
        let filtered = availableNetworks.filter { !hiddenList.contains($0) }
        if networkSearchText.isEmpty {
            addableNetworks = filtered
        } else {
            addableNetworks = filtered.filter { $0.localizedCaseInsensitiveContains(networkSearchText) }
        }
    }
    
    private func toggleHidden(_ name: String) {
        var hidden = hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }
        if let index = hidden.firstIndex(of: name) {
            hidden.remove(at: index)
        } else {
            hidden.append(name)
        }
        hiddenStudios = hidden.joined(separator: ",")
        LibraryStatsActor.clearCache()
    }
}
