import XCTest
@testable import DocNest

final class DocNestTests: XCTestCase {
    func testSampleDataExists() {
        XCTAssertFalse(DocumentRecord.samples.isEmpty)
    }
}