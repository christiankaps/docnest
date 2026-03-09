import SwiftUI

enum LibrarySection: String, CaseIterable, Identifiable {
    case allDocuments = "All Documents"
    case recent = "Recent Imports"
    case needsLabels = "Needs Labels"

    var id: String { rawValue }
}

struct LibrarySidebarView: View {
    @Binding var selectedSection: LibrarySection

    var body: some View {
        List(LibrarySection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: iconName(for: section))
                .tag(section)
        }
        .navigationTitle("Library")
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
    LibrarySidebarView(selectedSection: .constant(.allDocuments))
}