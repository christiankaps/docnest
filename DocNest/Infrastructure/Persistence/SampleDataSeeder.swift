import Foundation
import SwiftData

enum SampleDataSeeder {
    @MainActor
    static func seedIfNeeded(using context: ModelContext) throws {
        let descriptor = FetchDescriptor<DocumentRecord>()
        let existingCount = try context.fetchCount(descriptor)
        guard existingCount == 0 else { return }

        let labels = LabelTag.makeSamples()
        context.insert(labels.finance)
        context.insert(labels.tax)
        context.insert(labels.contracts)

        let documents = DocumentRecord.makeSamples(labels: labels)
        for document in documents {
            context.insert(document)
        }

        try context.save()
    }
}
