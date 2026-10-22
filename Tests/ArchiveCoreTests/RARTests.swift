import XCTest
@testable import ArchiveCore

final class RARTests: XCTestCase {
    var engine: ArchiveEngine!
    var root: URL!
    var fixtures: URL!
    override func setUpWithError() throws {
        let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable:project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
        fixtures = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciRAR-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func testOfficialRAR5CompressedFixtureExtractsExactSize() throws {
        let archive = fixtures.appendingPathComponent("test_read_format_rar5_compressed.rar")
        _ = try engine.extract(archive,destination:root)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("test.bin")).count,1200)
        try engine.verify(archive)
    }
    func testOfficialHeaderEncryptedRAR4AcceptsCorrectPassword() throws {
        let archive = fixtures.appendingPathComponent("test_read_format_rar_encryption_header.rar")
        XCTAssertThrowsError(try engine.list(archive))
        XCTAssertThrowsError(try engine.list(archive,password:"wrong"))
        let contents = try engine.list(archive,password:"12345678")
        XCTAssertFalse(contents.entries.isEmpty)
        _ = try engine.extract(archive,destination:root,password:"12345678")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    }
    func testOfficialMultipartSolidRAR5ExtractsFromAnyPart() throws {
        let archive = fixtures.appendingPathComponent("test_read_format_rar5_multiarchive_solid.part03.rar")
        let outcome = try engine.extract(archive,destination:root)
        XCTAssertEqual(outcome.fileCount,9)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("test.bin")).count,1200)
    }
    func testOfficialHeaderEncryptedRAR5ExtractsAllFourFiles() throws {
        let archive = fixtures.appendingPathComponent("test_read_format_rar5_encrypted_filenames.rar")
        XCTAssertThrowsError(try engine.list(archive))
        _ = try engine.extract(archive,destination:root,password:"password")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).count,4)
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("a.txt"),encoding:.utf8),"This is from a.txt")
    }
    func testRARExpandedSizeLimitStopsBeforePublishing() throws {
        let small = ArchiveEngine(executable:engine.executable,safety:SafetyPolicy(maximumExpandedBytes:100))
        XCTAssertThrowsError(try small.extract(fixtures.appendingPathComponent("test_read_format_rar5_compressed.rar"),destination:root))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    }
}
