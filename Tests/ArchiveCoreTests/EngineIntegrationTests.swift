import XCTest
@testable import ArchiveCore

final class EngineIntegrationTests: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable: package.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testZIPAnd7zRoundTripWithUnicodeAndShellCharacters() throws {
        let source = try file("Kaynak/çığ şü = $(dokun); 'x'.txt", "Merhaba dünya 🌍")
        for format in ArchiveFormat.allCases {
            let archive = root.appendingPathComponent("paket.\(format.rawValue)")
            _ = try engine.create(inputs: [source], destination: archive, format: format)
            let listing = try engine.list(archive)
            XCTAssertEqual(listing.entries.filter { !$0.isDirectory }.map(\.name), [source.lastPathComponent])
            let destination = root.appendingPathComponent("out-\(format.rawValue)")
            _ = try engine.extract(archive, destination: destination)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(source.lastPathComponent)), try Data(contentsOf: source))
            try engine.verify(archive)
        }
    }

    func testSelectiveExtractionAndCollisionPolicies() throws {
        let a = try file("in/one.txt", "new")
        let b = try file("in/two.txt", "two")
        let archive = root.appendingPathComponent("selection.zip")
        _ = try engine.create(inputs: [a,b], destination: archive)
        let out = root.appendingPathComponent("out")
        _ = try engine.extract(archive, destination: out, selected: ["one.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("two.txt").path))
        try Data("old".utf8).write(to: out.appendingPathComponent("one.txt"))
        let skip = try engine.extract(archive, destination: out, selected: ["one.txt"], collision: .skip)
        XCTAssertEqual(skip.skippedCount, 1)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("one.txt"), encoding: .utf8), "old")
        _ = try engine.extract(archive, destination: out, selected: ["one.txt"], collision: .rename)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("one (2).txt"), encoding: .utf8), "new")
        _ = try engine.extract(archive, destination: out, selected: ["one.txt"], collision: .replace)
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("one.txt"), encoding: .utf8), "new")
    }

    func testEncryptedArchiveAcceptsStdinPasswordAndRejectsWrongPassword() throws {
        let source = try file("secret.txt", "Gizli içerik")
        let archive = root.appendingPathComponent("encrypted.7z")
        _ = try engine.create(inputs: [source], destination: archive, format: .sevenZip, password: "şifre-42")
        XCTAssertThrowsError(try engine.list(archive))
        XCTAssertThrowsError(try engine.list(archive, password: "yanlış"))
        XCTAssertEqual(try engine.list(archive, password: "şifre-42").entries.first?.path, "secret.txt")
        _ = try engine.extract(archive, destination: root.appendingPathComponent("private"), password: "şifre-42")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("private/secret.txt"), encoding: .utf8), "Gizli içerik")
    }

    func testCreationPreservesExistingOutputAndCleansMetadata() throws {
        let source = try file("folder/file.txt", "real")
        _ = try file("folder/.DS_Store", "metadata")
        let archive = root.appendingPathComponent("exists.zip")
        try Data("existing".utf8).write(to: archive)
        let result = try engine.create(inputs: [source.deletingLastPathComponent()], destination: archive, cleanMetadata: true)
        XCTAssertNotEqual(result.url, archive)
        XCTAssertEqual(try String(contentsOf: archive, encoding: .utf8), "existing")
        XCTAssertFalse(try engine.list(result.url).entries.contains { $0.name == ".DS_Store" })
    }

    func testCancellationBeforeStartAndOutputInsideInputAreRejected() throws {
        let source = try file("folder/file", "a")
        let cancelled = OperationControl(); cancelled.cancel()
        XCTAssertThrowsError(try engine.create(inputs: [source], destination: root.appendingPathComponent("cancel.zip"), control: cancelled))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel.zip").path))
        XCTAssertThrowsError(try engine.create(inputs: [source.deletingLastPathComponent()], destination: source.deletingLastPathComponent().appendingPathComponent("loop.zip")))
    }

    func testDestinationSymlinkCannotRedirectPublication() throws {
        let source = try file("input/sub/file.txt", "new")
        let archive = root.appendingPathComponent("links.zip")
        _ = try engine.create(inputs: [source.deletingLastPathComponent()], destination: archive)
        let destination = root.appendingPathComponent("out")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("sub"), withDestinationURL: outside)
        XCTAssertThrowsError(try engine.extract(archive, destination: destination, collision: .replace))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("file.txt").path))
    }

    func testLiteralWildcardsDoNotIncludeUnselectedSiblings() throws {
        let source = try file("wild/report*.txt", "selected")
        _ = try file("wild/report-private.txt", "NOT SELECTED")
        let archive = root.appendingPathComponent("wild.zip")
        _ = try engine.create(inputs: [source], destination: archive)
        XCTAssertEqual(try engine.list(archive).entries.map(\.path), ["report*.txt"])
    }

    func testExtractionCannotOverwriteTheSourceArchive() throws {
        let source = try file("input/self.zip", "OVERWRITTEN")
        let archive = root.appendingPathComponent("self.zip")
        _ = try engine.create(inputs: [source], destination: archive)
        let original = try Data(contentsOf: archive)
        XCTAssertThrowsError(try engine.extract(archive, destination: root, collision: .replace))
        XCTAssertEqual(try Data(contentsOf: archive), original)
    }

    func testArchiveChangedAfterListingIsNotPublished() throws {
        let source = try file("input/a.txt", "original")
        let changed = try file("other/b.txt", "new input")
        let archive = root.appendingPathComponent("first.zip")
        let other = root.appendingPathComponent("other.zip")
        _ = try engine.create(inputs: [source], destination: archive)
        _ = try engine.create(inputs: [changed], destination: other)
        let replacement = try Data(contentsOf: other)
        let out = root.appendingPathComponent("changed-out")
        XCTAssertThrowsError(try engine.extract(archive, destination: out, progress: { update in
            if update.message == "Dosyalar çıkarılıyor…" { try? replacement.write(to: archive) }
        }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("b.txt").path))
    }

    func testSanitizedControlCharacterNamesFailClearlyBeforePublishing() throws {
        let source = try file("control/safe\nOdd = value", "data")
        let archive = root.appendingPathComponent("control.zip")
        let p = Process(); p.executableURL = engine.executable
        p.arguments = ["a", "-tzip", "--", archive.path, source.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); XCTAssertEqual(p.terminationStatus, 0)
        let listing = try engine.list(archive)
        let out = root.appendingPathComponent("control-out")
        XCTAssertThrowsError(try engine.extract(archive, destination: out, selected: listing.entries.map(\.path)))
    }
}
