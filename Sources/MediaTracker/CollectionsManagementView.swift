import SwiftUI
import SwiftData

struct CollectionsManagementView: View {
    @Bindable var viewModel: MediaViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaCollection.name) private var collections: [MediaCollection]
    @State private var showingCreateSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Spacer()
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("New Collection", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                
                if collections.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("No Collections Yet")
                            .font(.title2.bold())
                        Text("Create a collection to organize your favorite movies and shows.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250))], spacing: 24) {
                        ForEach(collections) { collection in
                            CollectionCard(collection: collection) {
                                withAnimation {
                                    viewModel.selectedCollectionName = collection.name
                                    viewModel.currentCollectionNote = collection.notes ?? ""
                                    viewModel.selectedCollectionID = collection.id
                                    viewModel.filterSubject.send()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateCollectionSheet()
        }
    }
}

struct CollectionCard: View {
    let collection: MediaCollection
    let onTap: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var isHovered = false
    @State private var showingEditSheet = false
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 140)
                
                Image(systemName: collection.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
            }
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    HStack(spacing: 8) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button(role: .destructive) {
                            modelContext.delete(collection)
                        } label: {
                            Image(systemName: "trash")
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
            }
            
            VStack(spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("\(collection.items.count) Items")
                    if !collection.completedItemIDs.isEmpty {
                        Text("•")
                        Text("\(collection.completedItemIDs.count) Done")
                            .foregroundStyle(collection.completedItemIDs.count == collection.items.count ? .green : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(24)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .sheet(isPresented: $showingEditSheet) {
            CreateCollectionSheet(editingCollection: collection)
        }
    }
}

struct CreateCollectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var editingCollection: MediaCollection? = nil
    
    @State private var name = ""
    @State private var icon = "star.fill"
    @State private var iconSearchText = ""
    
    let suggestedIcons = [
        "star.fill", "heart.fill", "flame.fill", "bolt.fill", "sparkles", 
        "film", "tv", "popcorn.fill", "gamecontroller.fill", "music.note", 
        "book.fill", "briefcase.fill", "graduationcap.fill", "airplane", "car.fill",
        "globe", "map.fill", "moon.stars.fill", "sun.max.fill", "cloud.fill",
        "camera.fill", "video.fill", "theatermasks.fill", "music.quarternote.3", 
        "paintbrush.fill", "pencil.tip", "hammer.fill", "wrench.and.screwdriver.fill",
        "lightbulb.fill", "magnifyingglass", "cart.fill", "bag.fill", "creditcard.fill",
        "cross.case.fill", "pills.fill", "leaf.fill", "pawprint.fill", "fish.fill",
        "hare.fill", "tortoise.fill", "ant.fill", "ladybug.fill", "soccerball",
        "baseball.fill", "basketball.fill", "football.fill", "tennisball", 
        "volleyball.fill", "bicycle", "figure.walk", "figure.run",
        "trophy.fill", "medal.fill", "gift.fill", "crown.fill", "diamond.fill",
        "folder.fill", "archivebox.fill", "tray.fill", "paperplane.fill", "doc.text.fill",
        "calendar", "alarm.fill", "stopwatch.fill", "timer", "hourglass"
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
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Collection Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SF SYMBOL NAME")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                
                TextField("e.g. briefcase.fill", text: $icon)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SUGGESTIONS")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("Filter suggestions...", text: $iconSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .frame(width: 150)
                }
                
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(filteredIcons, id: \.self) { iconName in
                            Image(systemName: iconName)
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(icon == iconName ? Color.blue : Color.primary.opacity(0.05))
                                .foregroundStyle(icon == iconName ? .white : .primary)
                                .cornerRadius(10)
                                .onTapGesture {
                                    icon = iconName
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 140)
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
                
                Button(editingCollection == nil ? "Create" : "Save") {
                    if let editing = editingCollection {
                        editing.name = name
                        editing.systemImage = icon
                    } else {
                        let newCollection = MediaCollection(name: name, systemImage: icon)
                        modelContext.insert(newCollection)
                    }
                    dismiss()
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(name.isEmpty ? Color.gray.opacity(0.2) : Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 450)
        .onAppear {
            if let editing = editingCollection {
                name = editing.name
                icon = editing.systemImage
            }
        }
    }
}

struct NoteOverlayView: View {
    @Bindable var viewModel: MediaViewModel
    let collectionID: UUID
    @Environment(\.modelContext) private var modelContext
    @Query private var collections: [MediaCollection]
    
    @State private var localNote: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "pencil.and.outline")
                            .foregroundStyle(.blue)
                        Text("Collection Notes")
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation {
                                viewModel.showingNoteOverlay = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    TextEditor(text: $localNote)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        .frame(minHeight: 100, maxHeight: 200)
                        .focused($isFocused)
                        .overlay(alignment: .topLeading) {
                            if localNote.isEmpty {
                                Text("Add a note for this collection...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(20)
                .frame(width: 320)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                }
                .padding(.top, 60)
                .padding(.trailing, 20)
            }
            Spacer()
        }
        .onAppear {
            if let col = collections.first(where: { $0.id == collectionID }) {
                localNote = col.notes ?? ""
            }
            isFocused = true
        }
        .onChange(of: localNote) { _, newValue in
            viewModel.currentCollectionNote = newValue
            saveNote(newValue)
        }
    }
    
    private func saveNote(_ text: String) {
        // Simple synchronous save since it's just a string update
        if let col = collections.first(where: { $0.id == collectionID }) {
            col.notes = text
            try? modelContext.save()
        }
    }
}
