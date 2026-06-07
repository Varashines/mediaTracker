import SwiftUI
import SwiftData

struct StudioAliasManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NetworkEntity.name) private var networks: [NetworkEntity]
    @Query(sort: \StudioAliasEntity.target) private var aliasEntities: [StudioAliasEntity]
    @AppStorage("studio_aliases") private var legacyAliases = ""

    @State private var showingAddGroup = false
    @State private var newGroupName = ""
    @State private var showAllNetworks = false

    private var availableNetworks: [String] {
        networks.map { $0.name }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupListSection
            addButtonSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .font(.system(size: 24, weight: .bold, design: .rounded))
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func sourcePicker(entity: StudioAliasEntity) -> some View {
        let displayNetworks = showAllNetworks ? availableNetworks : Array(availableNetworks.prefix(20))
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayNetworks, id: \.self) { net in
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
                            .background(isSelected ? AppTheme.Colors.accent.opacity(0.15) : Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay {
                                if isSelected {
                                    Capsule().stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                if availableNetworks.count > 20 {
                    Button {
                        showAllNetworks.toggle()
                        FeedbackManager.shared.trigger(.click)
                    } label: {
                        Text(showAllNetworks ? "Show Less" : "+\(availableNetworks.count - 20) More")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
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
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Text(src)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(isLogo ? AppTheme.Colors.accent : .secondary)
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            Button {
                withAnimation { showingAddGroup = true }
            } label: {
                Label("Add New Group", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.blue)
            }
            .buttonStyle(.plain)
        }
    }
    
    static func migrateLegacyAliases(from legacy: String, into container: ModelContainer) {
        guard !legacy.isEmpty else { return }
        let ctx = ModelContext(container)
        guard ((try? ctx.fetch(FetchDescriptor<StudioAliasEntity>())) ?? []).isEmpty else { return }

        let lines = legacy.components(separatedBy: .newlines)
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
            ctx.insert(StudioAliasEntity(target: target, sources: sources, preferredLogoSource: preferredLogoSource))
        }
        try? ctx.save()
    }
}
