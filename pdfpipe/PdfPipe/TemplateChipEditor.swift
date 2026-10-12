import SwiftUI

struct TemplateChipEditor: View {
    @Binding var template: String
    @State private var draft = ""
    @State private var editingLiteral: Int?

    private var parts: [FilenameTemplate.Part] { (try? FilenameTemplate.parse(template)) ?? [] }
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filename").font(.subheadline.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if parts.isEmpty { Text("Tap the parts below").foregroundStyle(.secondary) }
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        HStack(spacing: 4) {
                            if case .literal(let value) = part, value != "_", value != "-" {
                                Button(value) {
                                    draft = value
                                    editingLiteral = index
                                }.accessibilityLabel("Edit fixed text \(value)")
                            } else {
                                Text(part.title)
                            }
                            Button { remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Remove \(part.title)")
                            .accessibilityIdentifier("templatePart-\(index)")
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(PipeAppearance.accent.opacity(0.12), in: Capsule())
                    }
                }.padding(.vertical, 2)
            }
            .accessibilityIdentifier("filenameTemplate")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach([FilenameTemplate.Token.documentDate, .word1, .word2, .word3,
                         .original, .date, .text], id: \.self) { token in
                    Button(token.title) { append(.token(token)) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("addTemplate-\(token.rawValue)")
                }
                Button("_") { append(.literal("_")) }.buttonStyle(.bordered).accessibilityIdentifier("addTemplate-underscore")
                Button("-") { append(.literal("-")) }.buttonStyle(.bordered).accessibilityIdentifier("addTemplate-hyphen")
            }
            HStack {
                TextField("Fixed text", text: $draft)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("templateFixedText")
                Button(editingLiteral == nil ? "Add" : "Apply") {
                    guard !draft.isEmpty, !draft.contains("{"), !draft.contains("}") else { return }
                    if let editingLiteral {
                        replace(at: editingLiteral, with: .literal(draft))
                        self.editingLiteral = nil
                    } else { append(.literal(draft)) }
                    draft = ""
                }.disabled(draft.isEmpty || draft.contains("{") || draft.contains("}"))
            }
            if draft.contains("{") || draft.contains("}") {
                Text("Braces are reserved for template parts.").font(.caption).foregroundStyle(.red)
            }
            Button("Clear template", role: .destructive) {
                template = ""
                editingLiteral = nil
                draft = ""
            }.font(.caption)
            Text("Document date uses the date found in the PDF, or today's date when none is found. Processing date always uses today's date. The .pdf extension is added automatically.")
                .font(.caption).foregroundStyle(.secondary)
            if let preview = try? FilenameTemplate.render(template, values: .init(original: "Invoice",
                manualText: "Acme", processedAt: Date(), documentDate: "2026-10-05",
                words: ["Telekom", "Rechnung", "Internet"])) {
                Text("Example: \(preview)").font(.caption).foregroundStyle(PipeAppearance.accent)
                    .accessibilityIdentifier("templateExample")
            }
        }
    }

    private func append(_ part: FilenameTemplate.Part) { template = FilenameTemplate.source(parts + [part]) }
    private func remove(at index: Int) {
        var updated = parts
        updated.remove(at: index)
        template = FilenameTemplate.source(updated)
        editingLiteral = nil
    }
    private func replace(at index: Int, with part: FilenameTemplate.Part) {
        var updated = parts
        updated[index] = part
        template = FilenameTemplate.source(updated)
    }
}
