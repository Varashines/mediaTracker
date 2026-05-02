import SwiftUI
import SwiftData

struct DiscoveryManagementView: View {
    @Query(sort: \NetworkEntity.name) private var networkEntities: [NetworkEntity]
    @AppStorage("hidden_studios") private var hiddenStudios: String = ""
    @State private var availableNetworks: [String] = []
    @State private var networkSearchText = ""
    @Environment(\.colorScheme) var colorScheme

    private var hiddenList: [String] {
        hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }.sorted()
    }
    
    private var addableNetworks: [String] {
        let filtered = availableNetworks.filter { !hiddenList.contains($0) }
        if networkSearchText.isEmpty {
            return filtered.sorted()
        } else {
            return filtered.filter { $0.localizedCaseInsensitiveContains(networkSearchText) }.sorted()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Search and Add Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Search & Add Networks")
                    .font(.system(size: 13, weight: .bold))
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
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 10))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.primary.opacity(0.08))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 44)
                } else if !networkSearchText.isEmpty {
                    Text("No matching networks found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
            }
            
            Divider()

            // 2. Hidden Networks Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Hidden from Discovery")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 0) {
                    if hiddenList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 24))
                            Text("All networks are currently visible.")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(hiddenList, id: \.self) { name in
                            HStack {
                                Text(name)
                                    .font(.system(size: 14, weight: .medium))
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
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { calculateNetworks() }
    }
    
    private func toggleHidden(_ name: String) {
        var hidden = hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }
        if let index = hidden.firstIndex(of: name) {
            hidden.remove(at: index)
        } else {
            hidden.append(name)
        }
        hiddenStudios = hidden.joined(separator: ",")
    }

    private func calculateNetworks() {
        availableNetworks = networkEntities.map { $0.name }.sorted()
    }
}
