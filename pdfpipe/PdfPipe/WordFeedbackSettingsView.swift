import SwiftUI

struct WordFeedbackSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var votes = WordFeedback.load()
    @State private var showingClearConfirmation = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hold a suggested word to mark it more or less important. Ratings affect future imports only. They never choose a filename for you.")
                        .foregroundStyle(.secondary)
                }
                Section("Rated words") {
                    if votes.isEmpty {
                        Text("No words rated yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(votes.keys.sorted(), id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Label(votes[word] == 1 ? "More important" : "Less important",
                                      systemImage: votes[word] == 1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { remove(word) }
                            }
                        }
                    }
                }
                if !votes.isEmpty {
                    Section {
                        Button("Clear all ratings", role: .destructive) { showingClearConfirmation = true }
                    }
                }
            }
            .navigationTitle("Word ratings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all word ratings?", isPresented: $showingClearConfirmation) {
                Button("Clear all ratings", role: .destructive) { clear() }
            }
            .alert("Word ratings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .tint(PipeAppearance.accent)
    }

    private func remove(_ word: String) {
        do { votes = try WordFeedback.remove(word) }
        catch { self.error = error.localizedDescription }
    }

    private func clear() {
        do {
            try WordFeedback.clear()
            votes = [:]
        } catch { self.error = error.localizedDescription }
    }
}
