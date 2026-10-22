import XCTest
@testable import ArchiveCore

final class NativePreviewTests: XCTestCase {
    var fixtures: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }
    func testRAR5NativeListingNeedsNoChildProcess() throws {
        let contents = try NativePreviewReader.list(fixtures.appendingPathComponent("test_read_format_rar5_compressed.rar"))
        XCTAssertEqual(contents.entries.map(\.path),["test.bin"])
        XCTAssertEqual(contents.totalSize,1200)
    }
    func testZIPAnd7zNativePreviewKeepUnicodePaths() throws {
        let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativePreview-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let source = root.appendingPathComponent("Türkçe.txt"); try Data("Merhaba".utf8).write(to:source)
        let engine = ArchiveEngine(executable:project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
        for format in ArchiveFormat.allCases {
            let archive = root.appendingPathComponent("test.\(format.rawValue)")
            _ = try engine.create(inputs:[source],destination:archive,format:format)
            XCTAssertEqual(try NativePreviewReader.list(archive).entries.map(\.path),["Türkçe.txt"])
        }
    }
    func testHeaderEncryptedPreviewExplainsPasswordRequirement() throws {
        XCTAssertThrowsError(try NativePreviewReader.list(fixtures.appendingPathComponent("test_read_format_rar5_encrypted_filenames.rar"))) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("parola"),error.localizedDescription)
        }
    }
    func testNativePreviewRejectsCancelledInput() throws {
        let control = OperationControl(); control.cancel()
        XCTAssertThrowsError(try NativePreviewReader.list(fixtures.appendingPathComponent("test_read_format_rar5_compressed.rar"),control:control)) { error in XCTAssertEqual(error as? ArchiveFailure,.cancelled) }
    }
}
