import SwiftUI
import SwiftData

enum LibrarySection: String, CaseIterable, Identifiable {
    case allDocuments = "All Documents"
    case recent = "Recent Imports"
    case needsLabels = "Needs Labels"

    var id: String { rawValue }
}

struct LibrarySidebarView: View {
    @Binding var selectedSection: LibrarySection
    let labels: [LabelTag]
    @Binding var selectedLabelIDs: Set<PersistentIdentifier>

    var body: some View {
        List {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack {
                            Label(section.rawValue, systemImage: iconName(for: section))
                            Spacer()
                            if selectedSection == section {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Label Filters") {
                if labels.isEmpty {
                    Text("No labels yet")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Clear Label Filters") {
                        selectedLabelIDs.removeAll()
                    }
                    .disabled(selectedLabelIDs.isEmpty)

                    ForEach(labels) { label in
                        Button {
                            toggleLabelSelection(label)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(label.labelColor.color)
                                    .frame(width: 10, height: 10)
                                Text(label.name)
                                Spacer()
                                if selectedLabelIDs.contains(label.persistentModelID) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Library")
    }

    private func toggleLabelSelection(_ label: LabelTag) {
        let labelID = label.persistentModelID
        if selectedLabelIDs.contains(labelID) {
            selectedLabelIDs.remove(labelID)
        } else {
            selectedLabelIDs.insert(labelID)
        }
    }

    private func iconName(for section: LibrarySection) -> String {
        switch section {
        case .allDocuments:
            "doc.richtext"
        case .recent:
            "clock"
        case .needsLabels:
            "tag.slash"
        }
    }
}

#Preview {
    let labels = LabelTag.makeSamples()
    LibrarySidebarView(
        selectedSection: .constant(.allDocuments),
        labels: [labels.finance, labels.tax, labels.contracts],
        selectedLabelIDs: .constant([])
    )
}