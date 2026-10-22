import XCTest
import ArchiveCore
@testable import SikistiriciApp

final class AppSessionTests: XCTestCase {
    @MainActor func testClosingArchiveDismissesAndInvalidatesPreview() {
        let model = AppModel()
        model.showingPreview = true; model.previewLoading = true
        model.previewURL = URL(fileURLWithPath: "/temporary/old.txt")
        model.closeArchive()
        XCTAssertFalse(model.showingPreview)
        XCTAssertFalse(model.previewLoading)
        XCTAssertNil(model.previewURL)
    }
    @MainActor func testOpeningAnotherArchiveDismissesOldPreview() {
        let model = AppModel()
        model.showingPreview = true; model.previewLoading = true
        model.previewURL = URL(fileURLWithPath: "/temporary/old.txt")
        model.openArchive(URL(fileURLWithPath: "/nonexistent/sikistirici-test.zip"))
        XCTAssertFalse(model.showingPreview)
        XCTAssertFalse(model.previewLoading)
        XCTAssertNil(model.previewURL)
        model.closeArchive()
    }
    @MainActor func testFinishedEditDoesNotReopenAnArchiveTheUserLeft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciSession-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine = ArchiveEngine(executable:project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
        let input = root.appendingPathComponent("a.txt"); try Data("A".utf8).write(to:input)
        let archive = root.appendingPathComponent("one.zip")
        _ = try engine.create(inputs:[input],destination:archive)
        let model = AppModel(); model.archiveURL = archive
        model.enqueue(.edit(archive,ArchiveChanges(renames:["a.txt":"b.txt"]),nil,nil),title:"Edit",subtitle:"")
        let other = root.appendingPathComponent("other.zip")
        model.archiveURL = other
        for _ in 0..<150 where model.hasPendingJobs { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(model.hasPendingJobs)
        XCTAssertEqual(model.archiveURL,other)
        model.closeArchive()
    }
}
