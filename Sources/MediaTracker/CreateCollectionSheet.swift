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
        VStack(spacing: 24) {
            Text(editingCollection == nil ? "New Collection" : "Edit Collection")
                .font(.system(.title2, design: .rounded)).bold()
            
            VStack(alignment: .leading, spacing: 20) {
                // Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .kerning(1)
                    TextField("Collection Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(16)
                }
                
                // Smart Playlist Toggle
                Toggle(isOn: $isSmart.animation(.spring)) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(.purple.opacity(0.1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .font(.system(size: 14, weight: .bold))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Playlist")
                                .font(.system(.headline, design: .rounded))
                            Text("Dynamic rules to group media.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding()
                .background(Color.primary.opacity(0.03))
                .cornerRadius(16)
                
                if isSmart {
                    smartRulesSection
                }
                
                // Icon Picker
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ICON")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .kerning(1)
                        Spacer()
                        TextField("Search symbols...", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(10)
                            .frame(width: 180)
                    }
                    
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(filteredIcons, id: \.self) { iconName in
                                Image(systemName: iconName)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(icon == iconName ? Color.blue.gradient : Color.primary.opacity(0.05).gradient)
                                    .foregroundStyle(icon == iconName ? .white : .primary)
                                    .cornerRadius(14)
                                    .onTapGesture {
                                        withAnimation(.spring) { icon = iconName }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: 180)
                }
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(.body, design: .rounded)).bold()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(16)
                
                Button(editingCollection == nil ? "Create" : "Save") {
                    if let editing = editingCollection {
                        editing.name = name
                        editing.systemImage = icon
                        editing.isSmart = isSmart
                        editing.smartRules = smartRules
                    } else {
                        let newCollection = MediaCollection(name: name, systemImage: icon, isSmart: isSmart)
                        if isSmart { newCollection.smartRules = smartRules }
                        modelContext.insert(newCollection)
                    }
                    dismiss()
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                .font(.system(.body, design: .rounded)).bold()
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(name.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.2)) : AnyShapeStyle(Color.blue.gradient))
                .foregroundStyle(.white)
                .cornerRadius(16)
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
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.secondary)
                    .kerning(1)
                Spacer()
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
                        Button("Comedy") { smartRules.append(.genre("Comedy")) }
                        Button("Drama") { smartRules.append(.genre("Drama")) }
                        Button("Sci-Fi") { smartRules.append(.genre("Science Fiction")) }
                        Button("Horror") { smartRules.append(.genre("Horror")) }
                    }
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            
            if smartRules.isEmpty {
                Text("Includes everything in your library.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(smartRules.enumerated()), id: \.offset) { idx, rule in
                        HStack {
                            ruleLabel(for: rule)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Spacer()
                            Button {
                                smartRules.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
        .cornerRadius(16)
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
        }
    }
}
