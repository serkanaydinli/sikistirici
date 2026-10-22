import XCTest
@testable import ArchiveCore

final class CoreAuditRegressionTests: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CoreAudit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable: package.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    func testPreflightConflictPreservesOldFile() throws {
        try file("stage/bundle/a.txt", "NEW")
        try file("stage/bundle/z/inside.txt", "inside")
        let old = try file("out/bundle/a.txt", "OLD")
        try file("out/bundle/z", "block")
        XCTAssertThrowsError(try FilePublisher.publish(root.appendingPathComponent("stage"), to: root.appendingPathComponent("out"), policy: .replace, control: OperationControl(), protectedSources: []))
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "OLD")
    }
    func testNestedColonRejectedWithoutPublishing() throws {
        let source = try file("input/with:colon.txt", "original")
        let output = root.appendingPathComponent("bad.zip")
        XCTAssertThrowsError(try engine.create(inputs: [source.deletingLastPathComponent()], destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }
    func testSelectedLeavesBudgetAndRoundTrip() throws {
        let tiny = try file("input/tiny.txt", "tiny")
        try Data(repeating: 0, count: 10 * 1024 * 1024).write(to: root.appendingPathComponent("input/big.bin"))
        let archive = try engine.create(inputs: [tiny.deletingLastPathComponent()], destination: root.appendingPathComponent("ok.zip"))
        try engine.verify(archive.url)
        let constrained = ArchiveEngine(executable: engine.executable, capacityProvider: { _ in 9 * 1024 * 1024 })
        let out = root.appendingPathComponent("out")
        XCTAssertNoThrow(try constrained.extract(archive.url, destination: out, selected: ["input/tiny.txt", "input/tiny.txt"]))
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("input/tiny.txt"), encoding: .utf8), "tiny")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("input/big.bin").path))
        let tooTight = ArchiveEngine(executable: engine.executable, capacityProvider: { _ in 8 * 1024 * 1024 + 3 })
        XCTAssertThrowsError(try tooTight.extract(archive.url, destination: root.appendingPathComponent("too-tight"), selected: ["input/tiny.txt"]))
    }
    func testErrorAndCancellationAfterChangesRestoreReplacementsAndRemoveNewFiles() throws {
        for cancel in [false, true] {
            let prefix = cancel ? "cancel" : "error"
            try file("\(prefix)/stage/a.txt", "NEW")
            try file("\(prefix)/stage/b.txt", "new file")
            try file("\(prefix)/stage/c.txt", "NEW C")
            let old = try file("\(prefix)/out/a.txt", "OLD")
            let oldC = try file("\(prefix)/out/c.txt", "OLD C")
            let originalDate = Date(timeIntervalSince1970: 1_000_000_000)
            try FileManager.default.setAttributes([.modificationDate: originalDate, .posixPermissions: 0o640], ofItemAtPath: old.path)
            let outputDirectory = root.appendingPathComponent("\(prefix)/out")
            try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: outputDirectory.path)
            let control = OperationControl()
            var changes = 0
            XCTAssertThrowsError(try FilePublisher.publish(root.appendingPathComponent("\(prefix)/stage"), to: root.appendingPathComponent("\(prefix)/out"), policy: .replace, control: control, protectedSources: [], afterChange: {
                changes += 1
                if changes == 2 {
                    XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "NEW")
                    if cancel { control.cancel() } else { throw ArchiveFailure.engine("Injected publication failure") }
                }
            }))
            XCTAssertEqual(changes, 2)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: outputDirectory.path)[.modificationDate] as? Date, originalDate)
            XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "OLD")
            XCTAssertEqual(try String(contentsOf: oldC, encoding: .utf8), "OLD C")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(prefix)/out/b.txt").path))
            let attributes = try FileManager.default.attributesOfItem(atPath: old.path)
            XCTAssertEqual(attributes[.modificationDate] as? Date, originalDate)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).contains { $0.hasPrefix(".sikistirici-recovery-") })
        }
    }
    func testFailedRollbackPreservesRecoveryOutsideStaging() throws {
        try file("stage/folder/a.txt", "NEW")
        try file("out/folder/a.txt", "OLD")
        let out = root.appendingPathComponent("out")
        XCTAssertThrowsError(try FilePublisher.publish(root.appendingPathComponent("stage"), to: out, policy: .replace, control: OperationControl(), protectedSources: [], afterChange: {
            try FileManager.default.moveItem(at: out.appendingPathComponent("folder"), to: self.root.appendingPathComponent("moved-folder"))
            try Data("blocking file".utf8).write(to: out.appendingPathComponent("folder"))
            throw ArchiveFailure.engine("Injected failure")
        })) { error in XCTAssertTrue(error.localizedDescription.contains(".sikistirici-recovery-")) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("stage"))
        let recovery = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".sikistirici-recovery-") })
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent("0"), encoding: .utf8), "OLD")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: recovery.appendingPathComponent("original-paths.json"))) as? [String: String]
        XCTAssertEqual(manifest?[out.appendingPathComponent("folder/a.txt").path], "0")
    }

    func testCreateVerifiesEngineOutputBeforePublication() throws {
        let source = try file("input.txt", "original")
        let script = try file("fake-engine", """
        #!/bin/sh
        case "$1" in
          a) for argument in "$@"; do case "$argument" in *.zip) printf corrupt > "$argument";; esac; done ;;
          l) printf 'Path = input.txt\\nSize = 8\\nAttributes = A\\n\\n' ;;
          t) exit 2 ;;
        esac
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let fake = ArchiveEngine(executable: script)
        let output = root.appendingPathComponent("bad-engine.zip")
        XCTAssertThrowsError(try fake.create(inputs: [source], destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
    }

    func testReplacementNeedsOnlyWritableDestinationNotWritableParent() throws {
        try file("stage/a.txt", "NEW")
        let old = try file("locked/out/a.txt", "OLD")
        let parent = root.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path) }
        _ = try FilePublisher.publish(root.appendingPathComponent("stage"), to: parent.appendingPathComponent("out"), policy: .replace, control: OperationControl(), protectedSources: [])
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "NEW")
    }
    func testRollbackDoesNotRemoveUnexpectedFilesInCreatedDirectory() throws {
        try file("stage/folder/a.txt", "new")
        let output = root.appendingPathComponent("out")
        let unexpected = output.appendingPathComponent("folder/external.txt")
        XCTAssertThrowsError(try FilePublisher.publish(root.appendingPathComponent("stage"), to: output, policy: .replace, control: OperationControl(), protectedSources: [], afterChange: {
            try Data("external".utf8).write(to: unexpected)
            throw ArchiveFailure.engine("Injected failure")
        }))
        XCTAssertEqual(try String(contentsOf: unexpected, encoding: .utf8), "external")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("folder/a.txt").path))
    }

}
