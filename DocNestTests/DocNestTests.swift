import XCTest
import SwiftData
@testable import DocNest

final class DocNestTests: XCTestCase {
    @MainActor
    func testSampleDataCanBeSeeded() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        try SampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 3)
    }

    @MainActor
    func testSeedingIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        try SampleDataSeeder.seedIfNeeded(using: context)
        try SampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3, "Seeding should not duplicate data on second call")
    }
}