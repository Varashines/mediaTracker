import SwiftUI
import SwiftData

struct NoteOverlayView: View {
    @Bindable var viewModel: MediaViewModel
    let collectionID: UUID
    @Environment(\.modelContext) private var modelContext
    
    @State private var localNote: String = ""
    @State private var targetCollection: MediaCollection?
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
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
                            withAnimation(AppTheme.Animation.springSnappy) {
                                viewModel.collection.showingNoteOverlay = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    TextEditor(text: $localNote)
                        .font(AppTheme.Font.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(10)
                        .frame(minHeight: 100, maxHeight: 200)
                        .focused($isFocused)
                        .overlay(alignment: .topLeading) {
                            if localNote.isEmpty {
                                Text("Add a note for this collection...")
.font(AppTheme.Font.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(20)
                .frame(width: 320)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
                .padding(.top, 60)
                .padding(.trailing, 20)
            }
            Spacer()
        }
        .task(id: collectionID) {
            let descriptor = FetchDescriptor<MediaCollection>(
                predicate: #Predicate { $0.id == collectionID }
            )
            targetCollection = try? modelContext.fetch(descriptor).first
            if let col = targetCollection {
                localNote = col.notes ?? ""
            }
            isFocused = true
        }
        .onChange(of: localNote) { _, newValue in
            viewModel.collection.currentCollectionNote = newValue
            saveNote(newValue)
        }
    }
    
    private func saveNote(_ text: String) {
        targetCollection?.notes = text
        SaveCoordinator.shared.requestSave(modelContext)
    }
}
