import Testing
import Foundation
@testable import FB_Loader

@Suite("ExportProgress.removingSucceeded")
@MainActor
struct ExportProgressTests {

    @Test("снимает только успешно выгруженные книги")
    func removesOnlySucceeded() {
        let p = ExportProgress()
        p.succeeded = [1, 3]
        let result = p.removingSucceeded(from: [1, 2, 3, 4])
        #expect(result == [2, 4])
    }

    @Test("книги с ошибкой выгрузки остаются отмеченными")
    func keepsFailedChecked() {
        let p = ExportProgress()
        p.succeeded = [1]
        p.failed = [(title: "book 2", error: "not found")]
        let result = p.removingSucceeded(from: [1, 2])
        #expect(result == [2])
    }

    @Test("пустой succeeded — набор не меняется")
    func emptySucceededLeavesChecksUntouched() {
        let p = ExportProgress()
        let result = p.removingSucceeded(from: [1, 2, 3])
        #expect(result == [1, 2, 3])
    }

    @Test("libid'ы, отсутствующие в наборе, игнорируются")
    func orphanSucceededIgnored() {
        let p = ExportProgress()
        p.succeeded = [99]
        let result = p.removingSucceeded(from: [1, 2])
        #expect(result == [1, 2])
    }
}
