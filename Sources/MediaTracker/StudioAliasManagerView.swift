import SwiftUI
import SwiftData

struct StudioAliasManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [MediaItem]
    @AppStorage("studio_aliases") private var studioAliases = ""
    
    @State private var groups: [AliasGroup] = []
    @State private var availableNetworks: [String] = []
    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    
    struct AliasGroup: Identifiable {
        let id = UUID()
        var target: String
        var sources: Set<String>
        var preferredLogo: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupListSection
            addButtonSection
        }
        .onAppear { 
            calculateNetworks()
            load()
        }
    }

    @ViewBuilder
    private var groupListSection: some View {
        VStack(spacing: 12) {
            if groups.isEmpty {
                emptyGroupsView
            } else {
                ForEach($groups) { $group in
                    groupRow(group: $group)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyGroupsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24))
            Text("No studio groups created.")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private func groupRow(group: Binding<AliasGroup>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader(group: group)
            sourcePicker(group: group)
            logoPicker(group: group)
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func groupHeader(group: Binding<AliasGroup>) -> some View {
        HStack {
            Text(group.wrappedValue.target)
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Button { 
                groups.removeAll { $0.id == group.id }
                save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sourcePicker(group: Binding<AliasGroup>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableNetworks, id: \.self) { net in
                    let isSelected = group.wrappedValue.sources.contains(net)
                    Button {
                        if isSelected {
                            group.wrappedValue.sources.remove(net)
                            if group.wrappedValue.preferredLogo == net { group.wrappedValue.preferredLogo = nil }
                        } else {
                            group.wrappedValue.sources.insert(net)
                        }
                        save()
                        FeedbackManager.shared.trigger(.click)
                    } label: {
                        Text(net)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay {
                                if isSelected {
                                    Capsule().stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func logoPicker(group: Binding<AliasGroup>) -> some View {
        if !group.wrappedValue.sources.isEmpty {
            HStack(spacing: 10) {
                Text("Logo Source:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                ForEach(Array(group.wrappedValue.sources).sorted(), id: \.self) { src in
                    let isLogo = group.wrappedValue.preferredLogo == src
                    Button {
                        group.wrappedValue.preferredLogo = src
                        save()
                        FeedbackManager.shared.trigger(.click)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isLogo ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                            Text(src)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(isLogo ? Color.blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var addButtonSection: some View {
        if showingAddGroup {
            HStack {
                TextField("Group Name (e.g. Disney)", text: $newGroupName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Button("Create") {
                    if !newGroupName.isEmpty {
                        groups.append(AliasGroup(target: newGroupName, sources: [], preferredLogo: nil))
                        newGroupName = ""
                        showingAddGroup = false
                        save()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Cancel") { showingAddGroup = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            Button {
                withAnimation { showingAddGroup = true }
            } label: {
                Label("Add New Group", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.blue)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func calculateNetworks() {
        let allNets = items.compactMap { $0.cachedNetwork }
        availableNetworks = Array(Set(allNets)).sorted()
    }
    
    private func load() {
        let lines = studioAliases.components(separatedBy: .newlines)
        var parsed: [AliasGroup] = []
        
        for line in lines where line.contains("=") {
            let mainParts = line.components(separatedBy: "|")
            let aliasPart = mainParts[0]
            let logoPart = mainParts.count > 1 ? mainParts[1] : nil
            
            let sides = aliasPart.components(separatedBy: "=")
            guard sides.count >= 2 else { continue }
            
            let target = sides[0].trimmingCharacters(in: .whitespaces)
            let sources = sides[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            
            var preferredLogoSource: String? = nil
            if let logoStr = logoPart, logoStr.contains("Logo:") {
                preferredLogoSource = logoStr.components(separatedBy: "Logo:").last?.trimmingCharacters(in: .whitespaces)
            }
            
            parsed.append(AliasGroup(target: target, sources: Set(sources), preferredLogo: preferredLogoSource))
        }
        self.groups = parsed
    }
    
    private func save() {
        var output = ""
        for group in groups {
            let sourcesStr = Array(group.sources).sorted().joined(separator: ", ")
            var line = "\(group.target) = \(sourcesStr)"
            if let logo = group.preferredLogo {
                line += " | Logo: \(logo)"
            }
            output += line + "\n"
        }
        studioAliases = output.trimmingCharacters(in: .newlines)
    }
}
