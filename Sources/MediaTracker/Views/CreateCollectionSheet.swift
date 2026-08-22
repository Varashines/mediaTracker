import SwiftUI
import SwiftData

struct CreateCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var editingCollection: MediaCollection? = nil
    var initialIsSmart: Bool = false
    
    @State private var name = ""
    @State private var icon = "star.fill"
    @State private var iconSearchText = ""
    @State private var isSmart = false
    @State private var smartRules: [SmartRule] = []
    @State private var matchAny = false
    @State private var metadata: MediaFilterActor.LibraryMetadata?
    @State private var previewCount: Int?
    @State private var previewTask: Task<Void, Never>?
    @State private var expandedRuleIndex: Int?
    @FocusState private var isNameFocused: Bool
    
    let suggestedIcons = [
        // Media & Apps
        "star.fill", "heart.fill", "flame.fill", "bolt.fill", "sparkles", 
        "film", "tv", "popcorn.fill", "gamecontroller.fill", "music.note", "play.fill",
        "camera.fill", "video.fill", "theatermasks.fill", "paintbrush.fill",
        
        // Animals
        "pawprint.fill", "dog.fill", "cat.fill", "bird.fill", "ant.fill", "ladybug.fill",
        "fish.fill", "hare.fill", "tortoise.fill", "butterfly.fill", "lizard.fill",
        "monkey.fill", "bear.fill", "teddybear.fill", "owl.fill", "frog.fill",
        
        // Nature & Space
        "leaf.fill", "tree.fill", "mountain.2.fill", "sun.max.fill", "moon.stars.fill",
        "cloud.fill", "drop.fill", "rainbow", "globe.americas.fill", "tent.fill",
        "snowflake", "wind", "comet.fill",
        
        // Objects & Hobbies
        "gift.fill", "crown.fill", "trophy.fill", "medal.fill", "pills.fill",
        "briefcase.fill", "graduationcap.fill", "book.fill", "lightbulb.fill",
        "cart.fill", "bag.fill", "creditcard.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "umbrella.fill", "mug.fill", "cup.and.saucer.fill", "wineglass.fill", "fork.knife",
        "paintbrush.pointed.fill", "dice.fill", "puzzlepiece.fill",
        
        // Travel & Transport
        "airplane", "car.fill", "bicycle", "sailboat.fill", "map.fill", "tram.fill",
        "fuelpump.fill", "bed.double.fill",
        
        // Time & Organization
        "calendar", "alarm.fill", "stopwatch.fill", "timer", "hourglass", "archivebox.fill", "folder.fill",
        "paperplane.fill", "doc.text.fill", "keyboard", "mouse.fill"
    ]
    
    var filteredIcons: [String] {
        if iconSearchText.isEmpty {
            return suggestedIcons
        } else {
            return suggestedIcons.filter { $0.lowercased().contains(iconSearchText.lowercased()) }
        }
    }
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Text(editingCollection == nil ? "New Collection" : "Edit Collection")
                .font(AppTheme.Font.title2)
            
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    // Name Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(AppTheme.Font.caption2)
                            .foregroundStyle(.secondary)
                            .kerning(1.2)
                        TextField("Collection Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(AppTheme.Font.body)
                            .padding()
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(AppTheme.Radius.medium)
                            .focused($isNameFocused)
                            .onSubmit(saveCollection)
                    }
                
                    // Smart Playlist Toggle
                    if editingCollection == nil ? initialIsSmart : isSmart {
                    Toggle(isOn: $isSmart.animation(AppTheme.Animation.springSnappy)) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(AppTheme.Colors.accent.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "sparkles")
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .font(AppTheme.Font.heading)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Playlist")
                                    .font(AppTheme.Font.heading)
                                Text("Dynamic rules to group media.")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(AppTheme.Radius.medium)
                    .disabled(editingCollection != nil)
                    }
                
                    if isSmart {
                        smartRulesSection
                    }
                
                    // Icon Picker
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Search symbols...", text: $iconSearchText)
                                .textFieldStyle(.plain)
                                .font(AppTheme.Font.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(AppTheme.Radius.small)
                                .frame(width: 180)
                        
                            Spacer()
                        }
                    
                        IconPickerGridView(selectedIcon: $icon, filteredIcons: filteredIcons)
                    }
                }
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .font(AppTheme.Font.bodyBold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(AppTheme.Radius.medium)
                
                Button(editingCollection == nil ? "Create" : "Save") {
                    saveCollection()
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(AppTheme.Font.bodyBold)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(name.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.2)) : AnyShapeStyle(AppTheme.Colors.accent))
                .foregroundStyle(.white)
                .cornerRadius(AppTheme.Radius.medium)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding(32)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 560, idealHeight: 680)
        .onAppear {
            if let editing = editingCollection {
                name = editing.name
                icon = editing.systemImage
                isSmart = editing.isSmart
                smartRules = editing.smartRules
                matchAny = editing.smartMatchAny
            } else {
                isSmart = initialIsSmart
            }
            isNameFocused = true
        }
        .task {
            // Library-sourced values for the add/edit menus (genres, networks,
            // languages actually present in the user's library).
            let actor = MediaFilterActor.shared(modelContainer: modelContext.container)
            metadata = try? await actor.fetchLibraryMetadata()
        }
        .onChange(of: smartRules) { _, _ in scheduleCountPreview() }
        .onChange(of: matchAny) { _, _ in scheduleCountPreview() }
        .onDisappear { previewTask?.cancel() }
    }

    private func saveCollection() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let editing = editingCollection {
            editing.name = trimmedName
            editing.systemImage = icon
            if isSmart {
                editing.smartRuleSet = SmartRuleSet(matchAny: matchAny, rules: smartRules)
            } else {
                editing.smartRulesData = nil
            }
        } else {
            let newCollection = MediaCollection(name: trimmedName, systemImage: icon, isSmart: isSmart)
            if isSmart { newCollection.smartRuleSet = SmartRuleSet(matchAny: matchAny, rules: smartRules) }
            modelContext.insert(newCollection)
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MediaStateService.shared.postMediaStateChanged()
        }
    }

    /// Live "Matches N titles" — debounced, same evaluation path as saved collections.
    private func scheduleCountPreview() {
        previewTask?.cancel()
        guard isSmart, !smartRules.isEmpty else {
            previewCount = nil
            return
        }
        let ruleSet = SmartRuleSet(matchAny: matchAny, rules: smartRules)
        previewCount = nil
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let actor = MediaFilterActor.shared(modelContainer: modelContext.container)
            let count = (try? await actor.countPreview(matching: ruleSet)) ?? -1
            guard !Task.isCancelled else { return }
            previewCount = count
        }
    }
    
    @ViewBuilder
    private var smartRulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RULES")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                RuleAddMenu(smartRules: $smartRules, metadata: metadata)
            }

            if !smartRules.isEmpty {
                Picker("Match", selection: $matchAny) {
                    Text("Match All").tag(false)
                    Text("Match Any").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            if smartRules.isEmpty {
                Text("Includes everything in your library.")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(smartRules.enumerated()), id: \.offset) { idx, rule in
                        VStack(spacing: 0) {
                            HStack {
                                Label(rule.summaryLabel, systemImage: rule.symbolName)
                                    .font(AppTheme.Font.label)
                                Spacer()
                                Button {
                                    withAnimation(AppTheme.Animation.springGentle) {
                                        expandedRuleIndex = expandedRuleIndex == idx ? nil : idx
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(AppTheme.Font.caption)
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(expandedRuleIndex == idx ? 180 : 0))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .help("Edit rule")
                                Button {
                                    smartRules.remove(at: idx)
                                    if expandedRuleIndex == idx { expandedRuleIndex = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .help("Remove rule")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)

                            if expandedRuleIndex == idx {
                                RuleEditorRow(rule: binding(for: idx), metadata: metadata)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(10)
                                    .padding(.top, 6)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }

                    // Live match count — same evaluation as saved collections
                    HStack(spacing: 6) {
                        Image(systemName: "number.circle")
                            .foregroundStyle(.secondary)
                        if let count = previewCount {
                            Text(count >= 0 ? "Matches \(count) title\(count == 1 ? "" : "s")" : "Couldn't count matches")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Counting matches…")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .animation(AppTheme.Animation.springGentle, value: previewCount)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
        .cornerRadius(AppTheme.Radius.medium)
    }

    private func binding(for index: Int) -> Binding<SmartRule> {
        Binding(
            get: { smartRules[index] },
            set: { smartRules[index] = $0 }
        )
    }
    
}

/// Inline editor for one rule — value menus populated from the user's library
/// where applicable; fixed options for enums; free-form year entry.
struct RuleEditorRow: View {
    @Binding var rule: SmartRule
    var metadata: MediaFilterActor.LibraryMetadata?

    var body: some View {
        switch rule {
        case .genre(let current):
            valueMenu(
                title: "Genre",
                current: current,
                options: (metadata?.genres.map(\.name) ?? []).filter { !$0.isEmpty }
            ) { rule = .genre($0) }

        case .network(let current):
            valueMenu(
                title: "Network",
                current: current,
                options: metadata?.networks.map(\.name) ?? []
            ) { rule = .network($0) }

        case .language(let current):
            languageMenu(current: current)

        case .badge(let current):
            valueMenu(
                title: "Badge",
                current: current,
                options: ["NEW", "PREMIERE", "FINALE", "RETURNING", "BINGE", "BINGE DROP", "BEHIND"]
            ) { rule = .badge($0) }

        case .releaseYear(let year, let comp):
            yearEditor(start: Binding(
                get: { String(year) },
                set: { text in if let value = Int(text.trimmingCharacters(in: .whitespaces)) { rule = .releaseYear(value, comp) } }
            ), comparison: Binding(
                get: { comp },
                set: { rule = .releaseYear(year, $0) }
            ))

        case .releaseYearRange(let start, let end):
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM / TO YEAR")
                    .font(AppTheme.Font.caption2)
                    .foregroundStyle(.secondary)
                    .kerning(1.0)
                HStack(spacing: 12) {
                    yearField(String(start)) { if let v = Int($0) { rule = .releaseYearRange(v, max(v, end)) } }
                    Text("–").foregroundStyle(.secondary)
                    yearField(String(end)) { if let v = Int($0) { rule = .releaseYearRange(min(start, v), v) } }
                }
            }

        case .mediaType(let current):
            valueMenu(title: "Type", current: current.rawValue, options: MediaType.allCases.map(\.rawValue)) { raw in
                if let type = MediaType(rawValue: raw) { rule = .mediaType(type) }
            }

        case .state(let current):
            valueMenu(title: "Status", current: current.displayName, options: MediaState.allCases.map(\.displayName)) { display in
                if let state = MediaState.allCases.first(where: { $0.displayName == display }) { rule = .state(state) }
            }

        case .taste(let current):
            valueMenu(title: "Taste", current: current.rawValue, options: TasteValue.allCases.map(\.rawValue)) { raw in
                if let taste = TasteValue(rawValue: raw) { rule = .taste(taste) }
            }
        }
    }

    @ViewBuilder
    private func valueMenu(title: String, current: String, options: [String], assign: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
                .kerning(1.0)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { assign(option) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current.isEmpty ? "Choose…" : current)
                        .font(AppTheme.Font.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func languageMenu(current: String) -> some View {
        let nodes = metadata?.languages ?? []
        valueMenu(
            title: "Language",
            current: LanguageUtils.languageName(for: current),
            options: nodes.map { LanguageUtils.languageName(for: $0.code ?? $0.name) }
        ) { chosen in
            if let node = nodes.first(where: { LanguageUtils.languageName(for: $0.code ?? $0.name) == chosen }) {
                rule = .language(node.code ?? node.name)
            }
        }
    }

    @ViewBuilder
    private func yearEditor(start: Binding<String>, comparison: Binding<SmartRule.Comparison>) -> some View {
        HStack(spacing: 12) {
            yearField(start.wrappedValue) { start.wrappedValue = $0 }
            Menu {
                Button("is") { comparison.wrappedValue = .equals }
                Button("after") { comparison.wrappedValue = .after }
                Button("before") { comparison.wrappedValue = .before }
            } label: {
                HStack(spacing: 4) {
                    Text(comparison.wrappedValue.rawValue)
                        .font(AppTheme.Font.label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppTheme.Font.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func yearField(_ text: String, commit: @escaping (String) -> Void) -> some View {
        TextField("Year", text: Binding(
            get: { text },
            set: { commit($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 80)
        .font(AppTheme.Font.label)
    }
}

struct IconPickerGridView: View {
    @Binding var selectedIcon: String
    let filteredIcons: [String]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(filteredIcons, id: \.self) { iconName in
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) { selectedIcon = iconName }
                    } label: {
                        Image(systemName: iconName)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selectedIcon == iconName ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.primary.opacity(0.05)))
                            .foregroundStyle(selectedIcon == iconName ? .white : .primary)
                            .cornerRadius(AppTheme.Radius.small)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(iconName)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: 180)
    }
}

struct RuleAddMenu: View {
    @Binding var smartRules: [SmartRule]
    var metadata: MediaFilterActor.LibraryMetadata?

    // Fallbacks when library metadata hasn't loaded (or is empty) —
    // menus prefer the user's actual library values when available.
    private static let fallbackGenres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Music", "Mystery", "Romance", "Science Fiction", "Thriller", "War", "Western"]
    private static let fallbackNetworks = ["Netflix", "Apple TV+", "Disney+", "HBO", "Amazon", "Hulu", "Paramount", "Peacock", "BBC", "CBS", "NBC", "ABC", "FOX"]
    private static let fallbackLanguages: [(name: String, code: String)] = [("English", "en"), ("Hindi", "hi"), ("Spanish", "es"), ("French", "fr"), ("Japanese", "ja"), ("Korean", "ko"), ("German", "de"), ("Italian", "it"), ("Portuguese", "pt"), ("Chinese", "zh")]

    private var genres: [String] {
        let libraryGenres = (metadata?.genres ?? []).map(\.name).filter { !$0.isEmpty }
        return libraryGenres.isEmpty ? Self.fallbackGenres : libraryGenres
    }
    private var networks: [String] {
        let libraryNetworks = (metadata?.networks ?? []).map(\.name).filter { !$0.isEmpty }
        return libraryNetworks.isEmpty ? Self.fallbackNetworks : libraryNetworks
    }
    private var languages: [(name: String, code: String)] {
        let libraryLanguages = (metadata?.languages ?? []).compactMap { node -> (name: String, code: String)? in
            guard let code = node.code else { return nil }
            return (LanguageUtils.languageName(for: code), code)
        }
        return libraryLanguages.isEmpty ? Self.fallbackLanguages : libraryLanguages
    }

    var body: some View {
        Menu {
            Menu("Media Type") {
                Button("Only Movies") { smartRules.append(.mediaType(.movie)) }
                Button("Only TV Shows") { smartRules.append(.mediaType(.tvShow)) }
            }
            Menu("Status") {
                Button("In Progress") { smartRules.append(.state(.active)) }
                Button("Watchlist") { smartRules.append(.state(.wishlist)) }
                Button("Completed") { smartRules.append(.state(.completed)) }
            }
            Menu("Taste") {
                Button("Loved") { smartRules.append(.taste(.love)) }
                Button("Liked") { smartRules.append(.taste(.like)) }
            }
            Menu("Release Year") {
                Button("Exactly 2024") { smartRules.append(.releaseYear(2024, .equals)) }
                Button("After 2020") { smartRules.append(.releaseYear(2020, .after)) }
                Button("Before 2000") { smartRules.append(.releaseYear(2000, .before)) }
                Button("90s (1990-1999)") { smartRules.append(.releaseYearRange(1990, 1999)) }
                Button("80s (1980-1989)") { smartRules.append(.releaseYearRange(1980, 1989)) }
            }
            Menu("Genre") {
                ForEach(genres, id: \.self) { genre in
                    Button(genre) { smartRules.append(.genre(genre)) }
                }
            }
            Menu("Badges") {
                Button("Premiere") { smartRules.append(.badge("PREMIERE")) }
                Button("Binge") { smartRules.append(.badge("BINGE")) }
                Button("Binge Drop") { smartRules.append(.badge("BINGE DROP")) }
                Button("New") { smartRules.append(.badge("NEW")) }
                Button("Finale") { smartRules.append(.badge("FINALE")) }
                Button("Returning") { smartRules.append(.badge("RETURNING")) }
            }
            Menu("Network") {
                ForEach(networks, id: \.self) { network in
                    Button(network) { smartRules.append(.network(network)) }
                }
            }
            Menu("Language") {
                ForEach(languages, id: \.code) { language in
                    Button(language.name) { smartRules.append(.language(language.code)) }
                }
            }
        } label: {
            Label("Add Rule", systemImage: "plus.circle")
                .font(AppTheme.Font.caption)
        }
    }
}
