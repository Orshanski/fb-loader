import Testing
import Foundation
@testable import FB_Loader

@Suite("FB2DescriptionParser")
struct FB2DescriptionParserTests {
    @Test("parses sample.fb2 description")
    func parsesSample() throws {
        let url = try #require(TestBundleAnchor.bundle
            .url(forResource: "sample", withExtension: "fb2"))
        let data = try Data(contentsOf: url)
        let info = try FB2DescriptionParser.parse(data: data)
        #expect(info.bookTitle == "Война и мир")
        #expect(info.annotation?.contains("Эпопея") ?? false)
        #expect(info.dateWritten == "1869")
        #expect(info.translators.count == 1)
        #expect(info.translators[0].lastName == "Garnett")
        #expect(info.coverImageData != nil)
    }
}
