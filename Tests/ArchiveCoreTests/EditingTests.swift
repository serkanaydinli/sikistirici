import XCTest
@testable import ArchiveCore

final class EditingTests: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciEdit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable: project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func testDraftDoesNotChangeSourceAndSaveAppliesAddDeleteRename() throws {
        let a = try file("input/a.txt", "A")
        let b = try file("input/b.txt", "B")
        let extra = try file("extra.txt", "EXTRA")
        let archive = root.appendingPathComponent("edit.zip")
        _ = try engine.create(inputs: [a,b], destination: archive)
        let original = try Data(contentsOf: archive)
        let changes = ArchiveChanges(deletions: ["b.txt"], renames: ["a.txt":"Türkçe.txt"], additions: [extra])
        let projected = try changes.projectedEntries(try engine.list(archive).entries)
        XCTAssertEqual(Set(projected.map(\.path)), ["Türkçe.txt","extra.txt"])
        XCTAssertEqual(try Data(contentsOf: archive), original)
        _ = try engine.saveEdits(archive, changes: changes)
        XCTAssertEqual(Set(try engine.list(archive).entries.map(\.path)), ["Türkçe.txt","extra.txt"])
        _ = try engine.extract(archive, destination: root.appendingPathComponent("out"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("out/Türkçe.txt"), encoding: .utf8), "A")
    }
    func testConflictingRenameAndCancelledSavePreserveOriginal() throws {
        let a = try file("input/a", "A"), b = try file("input/b", "B")
        let archive = root.appendingPathComponent("edit.zip")
        _ = try engine.create(inputs: [a,b], destination: archive)
        let original = try Data(contentsOf: archive)
        XCTAssertThrowsError(try engine.saveEdits(archive, changes: ArchiveChanges(renames: ["a":"b"])))
        let control = OperationControl(); control.cancel()
        XCTAssertThrowsError(try engine.saveEdits(archive, changes: ArchiveChanges(deletions: ["a"]), control: control))
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertThrowsError(try engine.saveEdits(archive, changes: ArchiveChanges(renames: ["a":"../escape"])))
    }
    func testNestedFolderRenameAndEncrypted7zRemainEncrypted() throws {
        let a = try file("input/folder/a.txt", "PRIVATE")
        let archive = root.appendingPathComponent("edit.7z")
        _ = try engine.create(inputs: [a.deletingLastPathComponent()], destination: archive, format: .sevenZip, password: "şifre")
        _ = try engine.saveEdits(archive, changes: ArchiveChanges(renames: ["folder":"yeni"]), password: "şifre")
        XCTAssertThrowsError(try engine.list(archive))
        XCTAssertTrue(try engine.list(archive,password:"şifre").entries.contains { $0.path == "yeni/a.txt" })
    }
    func testPrivateDirectoryPermissionsSurviveEditAndExtraction() throws {
        let a = try file("input/private/a.txt", "PRIVATE")
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:a.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:a.path)
        let archive = root.appendingPathComponent("permissions.zip")
        _ = try engine.create(inputs:[a.deletingLastPathComponent()],destination:archive)
        _ = try engine.saveEdits(archive,changes:ArchiveChanges(renames:["private/a.txt":"private/new.txt"]))
        _ = try engine.extract(archive,destination:root.appendingPathComponent("out"))
        let folder = try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("out/private").path)
        let file = try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("out/private/new.txt").path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue,0o700)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testDraftRefusesRenameOfDeletedEntry() throws {
        XCTAssertThrowsError(try ArchiveChanges(deletions:["a"],renames:["a":"b"]).projectedEntries([ArchiveEntry(path:"a"),ArchiveEntry(path:"c")]))
    }
    func testSourceChangedBeforeSaveCommitIsPreserved() throws {
        let a = try file("input/a", "A")
        let archive = root.appendingPathComponent("edit.zip")
        _ = try engine.create(inputs: [a], destination: archive)
        XCTAssertThrowsError(try engine.saveEdits(archive, changes: ArchiveChanges(renames: ["a":"new"]), progress: { update in
            if update.message == "Değişiklikler kaydediliyor…" { try? Data("changed by somebody else".utf8).write(to: archive) }
        }))
        XCTAssertEqual(try String(contentsOf: archive, encoding: .utf8), "changed by somebody else")
    }
}
