import SwiftUI
import SwiftData

struct StudioAliasManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [MediaItem]
    @Query(sort: \StudioAliasEntity.target) private var aliasEntities: [StudioAliasEntity]
    @AppStorage("studio_aliases") private var legacyAliases = ""
    
    @State private var availableNetworks: [String] = []
    @State private var showingAddGroup = false
    @State private var newGroupName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupListSection
            addButtonSection
        }
        .onAppear { 
            calculateNetworks()
            migrateIfNeeded()
        }
    }

    @ViewBuilder
    private var groupListSection: some View {
        VStack(spacing: 12) {
            if aliasEntities.isEmpty {
                emptyGroupsView
            } else {
                ForEach(aliasEntities) { entity in
                    groupRow(entity: entity)
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
    private func groupRow(entity: StudioAliasEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader(entity: entity)
            sourcePicker(entity: entity)
            logoPicker(entity: entity)
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func groupHeader(entity: StudioAliasEntity) -> some View {
        HStack {
            Text(entity.target)
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Button { 
                modelContext.delete(entity)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sourcePicker(entity: StudioAliasEntity) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableNetworks, id: \.self) { net in
                    let isSelected = entity.sources.contains(net)
                    Button {
                        if isSelected {
                            entity.sources.removeAll { $0 == net }
                            if entity.preferredLogoSource == net { entity.preferredLogoSource = nil }
                        } else {
                            entity.sources.append(net)
                        }
                        try? modelContext.save()
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
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func logoPicker(entity: StudioAliasEntity) -> some View {
        if !entity.sources.isEmpty {
            HStack(spacing: 10) {
                Text("Logo Source:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                ForEach(entity.sources.sorted(), id: \.self) { src in
                    let isLogo = entity.preferredLogoSource == src
                    Button {
                        entity.preferredLogoSource = src
                        try? modelContext.save()
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
                        let newEntity = StudioAliasEntity(target: newGroupName)
                        modelContext.insert(newEntity)
                        try? modelContext.save()
                        newGroupName = ""
                        showingAddGroup = false
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
        let allNets = items.flatMap { item in
            item.cachedNetwork?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        }
        availableNetworks = Array(Set(allNets.filter { !$0.isEmpty })).sorted()
    }

    private func migrateIfNeeded() {
        guard aliasEntities.isEmpty && !legacyAliases.isEmpty else { return }
        
        let lines = legacyAliases.components(separatedBy: .newlines)
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
            
            modelContext.insert(StudioAliasEntity(target: target, sources: sources, preferredLogoSource: preferredLogoSource))
        }
        try? modelContext.save()
        legacyAliases = ""
    }
}
