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
    @State private var pickerMode = 0 // 0 for SF Symbols, 1 for Emojis
    
    let suggestedEmojis = [
        "🍿", "🎬", "📺", "🎭", "⭐️", "🔥", "💖", "👾", "🎮", "📚", "📅", "⏰", "📁", "💿", "📼", "🎟️", "🎙️", "👀", "🚨", "🏆", "🌟", "✨", "🍕", "🍔", "☕️", "🍺", "🍷", "🎉", "✈️", "🚗", "🏖️", "💤"
    ]
    
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
    
    var filteredEmojis: [String] {
        if iconSearchText.isEmpty {
            return suggestedEmojis
        } else {
            return suggestedEmojis.filter { $0.contains(iconSearchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text(editingCollection == nil ? "New Collection" : "Edit Collection")
                .font(AppTheme.Font.title2)
            
            VStack(alignment: .leading, spacing: 20) {
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
                }
                
                // Smart Playlist Toggle
                if editingCollection == nil ? initialIsSmart : isSmart {
                    Toggle(isOn: $isSmart.animation(AppTheme.Animation.springSnappy)) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(.purple.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
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
                        Picker("", selection: $pickerMode) {
                            Text("Symbols").tag(0)
                            Text("Emojis").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        
                        Spacer()
                        
                        TextField(pickerMode == 0 ? "Search symbols..." : "Search emojis...", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .font(AppTheme.Font.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(AppTheme.Radius.small)
                            .frame(width: 180)
                    }
                    
                    if pickerMode == 0 {
                        IconPickerGridView(selectedIcon: $icon, filteredIcons: filteredIcons)
                    } else {
                        EmojiPickerGridView(selectedIcon: $icon, filteredEmojis: filteredEmojis)
                    }
                }
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .font(AppTheme.Font.bodyBold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(AppTheme.Radius.medium)
                
                Button(editingCollection == nil ? "Create" : "Save") {
                    if let editing = editingCollection {
                        editing.name = name
                        editing.systemImage = icon
                        // Bug fix: only set rules if smart, otherwise clear the data
                        // to prevent manual collections from silently converting to smart
                        if isSmart {
                            editing.smartRules = smartRules
                        } else {
                            editing.smartRulesData = nil
                        }
                    } else {
                        let newCollection = MediaCollection(name: name, systemImage: icon, isSmart: isSmart)
                        if isSmart { newCollection.smartRules = smartRules }
                        modelContext.insert(newCollection)
                    }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        MediaStateService.shared.postMediaStateChanged()
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(name.isEmpty)
                .font(AppTheme.Font.bodyBold)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(name.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.2)) : AnyShapeStyle(.secondary))
                .foregroundStyle(.white)
                .cornerRadius(AppTheme.Radius.medium)
            }
            .padding(.top, 10)
        }
        .padding(32)
        .frame(width: 500)
        .onAppear {
            if let editing = editingCollection {
                name = editing.name
                icon = editing.systemImage
                isSmart = editing.isSmart
                smartRules = editing.smartRules
                if icon.isEmoji {
                    pickerMode = 1
                }
            } else {
                isSmart = initialIsSmart
            }
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
                RuleAddMenu(smartRules: $smartRules)
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
                        HStack {
                            ruleLabel(for: rule)
                                .font(AppTheme.Font.label)
                            Spacer()
                            Button {
                                smartRules.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Circle())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
        .cornerRadius(AppTheme.Radius.medium)
    }
    
    @ViewBuilder
    private func ruleLabel(for rule: SmartRule) -> some View {
        switch rule {
        case .genre(let g):
            Label("Genre: \(g)", systemImage: "tag.fill")
        case .releaseYear(let year, let comp):
            Label("Year \(comp.rawValue) \(year)", systemImage: "calendar")
        case .releaseYearRange(let start, let end):
            Label("Years: \(start) - \(end)", systemImage: "calendar.badge.clock")
        case .mediaType(let type):
            Label("Type: \(type.rawValue)", systemImage: type == .movie ? "film" : "tv")
        case .state(let state):
            Label("Status: \(state.displayName)", systemImage: state.iconName)
        case .taste(let taste):
            Label("Taste: \(taste.rawValue)", systemImage: taste.iconName)
        case .badge(let b):
            Label("Badge: \(b)", systemImage: "sparkles")
        case .network(let n):
            Label("Network: \(n)", systemImage: "antenna.radiowaves.left.and.right")
        case .language(let l):
            Label("Language: \(LanguageUtils.languageName(for: l))", systemImage: "character.bubble.fill")
        }
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
                Button("Action") { smartRules.append(.genre("Action")) }
                Button("Adventure") { smartRules.append(.genre("Adventure")) }
                Button("Animation") { smartRules.append(.genre("Animation")) }
                Button("Comedy") { smartRules.append(.genre("Comedy")) }
                Button("Crime") { smartRules.append(.genre("Crime")) }
                Button("Documentary") { smartRules.append(.genre("Documentary")) }
                Button("Drama") { smartRules.append(.genre("Drama")) }
                Button("Family") { smartRules.append(.genre("Family")) }
                Button("Fantasy") { smartRules.append(.genre("Fantasy")) }
                Button("History") { smartRules.append(.genre("History")) }
                Button("Horror") { smartRules.append(.genre("Horror")) }
                Button("Music") { smartRules.append(.genre("Music")) }
                Button("Mystery") { smartRules.append(.genre("Mystery")) }
                Button("Romance") { smartRules.append(.genre("Romance")) }
                Button("Sci-Fi") { smartRules.append(.genre("Science Fiction")) }
                Button("Thriller") { smartRules.append(.genre("Thriller")) }
                Button("War") { smartRules.append(.genre("War")) }
                Button("Western") { smartRules.append(.genre("Western")) }
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
                Button("Netflix") { smartRules.append(.network("Netflix")) }
                Button("Apple TV+") { smartRules.append(.network("Apple TV+")) }
                Button("Disney+") { smartRules.append(.network("Disney+")) }
                Button("HBO / Max") { smartRules.append(.network("HBO")) }
                Button("Amazon Prime") { smartRules.append(.network("Amazon")) }
                Button("Hulu") { smartRules.append(.network("Hulu")) }
                Button("Paramount+") { smartRules.append(.network("Paramount")) }
                Button("Peacock") { smartRules.append(.network("Peacock")) }
                Button("BBC") { smartRules.append(.network("BBC")) }
                Button("CBS") { smartRules.append(.network("CBS")) }
                Button("NBC") { smartRules.append(.network("NBC")) }
                Button("ABC") { smartRules.append(.network("ABC")) }
                Button("FOX") { smartRules.append(.network("FOX")) }
            }
            Menu("Language") {
                Button("English") { smartRules.append(.language("en")) }
                Button("Hindi") { smartRules.append(.language("hi")) }
                Button("Spanish") { smartRules.append(.language("es")) }
                Button("French") { smartRules.append(.language("fr")) }
                Button("Japanese") { smartRules.append(.language("ja")) }
                Button("Korean") { smartRules.append(.language("ko")) }
                Button("Thai") { smartRules.append(.language("th")) }
                Button("Malayalam") { smartRules.append(.language("ml")) }
                Button("Tamil") { smartRules.append(.language("ta")) }
                Button("Telugu") { smartRules.append(.language("te")) }
                Button("German") { smartRules.append(.language("de")) }
                Button("Italian") { smartRules.append(.language("it")) }
                Button("Portuguese") { smartRules.append(.language("pt")) }
                Button("Chinese") { smartRules.append(.language("zh")) }
            }
        } label: {
            Label("Add Rule", systemImage: "plus.circle")
                .font(AppTheme.Font.caption)
        }
    }
}

struct EmojiPickerGridView: View {
    @Binding var selectedIcon: String
    let filteredEmojis: [String]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(filteredEmojis, id: \.self) { emoji in
                    Button {
                        withAnimation(AppTheme.Animation.springSnappy) { selectedIcon = emoji }
                    } label: {
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selectedIcon == emoji ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.primary.opacity(0.05)))
                            .cornerRadius(AppTheme.Radius.small)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(emoji)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: 180)
    }
}
