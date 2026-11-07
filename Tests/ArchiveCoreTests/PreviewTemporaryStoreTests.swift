import XCTest
import Darwin
@testable import SikistiriciApp

final class PreviewTemporaryStoreTests: XCTestCase {
    private func isolatedRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewStoreTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testPrivateDirectoriesAndActiveSessionSurviveCleanup() throws {
        let root = try isolatedRoot()
        let first = try PreviewTemporaryStore(temporaryRoot: root)
        let preview = try first.makePreviewDirectory()
        try Data("private synthetic document".utf8).write(to: preview.appendingPathComponent("document.txt"))
        for path in [first.baseURL, first.sessionURL, preview] {
            let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber
            XCTAssertEqual(mode.intValue & 0o777, 0o700)
        }
        let second = try PreviewTemporaryStore(temporaryRoot: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preview.appendingPathComponent("document.txt").path))
        _ = second
        first.removePreview(preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
    }
    func testUnlockedOrphanIsCleanedButSymlinkTargetSurvives() throws {
        let root = try isolatedRoot()
        let first = try PreviewTemporaryStore(temporaryRoot: root)
        let orphan = first.baseURL.appendingPathComponent("session-\(UUID())")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data().write(to: orphan.appendingPathComponent(".lock"))
        try Data("synthetic secret".utf8).write(to: orphan.appendingPathComponent("plain.txt"))
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        let link = first.baseURL.appendingPathComponent("session-\(UUID())")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: orphan.appendingPathComponent("linked-outside"), withDestinationURL: outside)
        let second = try PreviewTemporaryStore(temporaryRoot: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("keep.txt"), encoding: .utf8), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        _ = second
    }
    func testSymlinkRootRejectedAndCleanupCannotRemoveOutsideDirectory() throws {
        let root = try isolatedRoot()
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("SikistiriciPreviews-v1"), withDestinationURL: outside)
        XCTAssertThrowsError(try PreviewTemporaryStore(temporaryRoot: root))
        try FileManager.default.removeItem(at: root.appendingPathComponent("SikistiriciPreviews-v1"))
        let store = try PreviewTemporaryStore(temporaryRoot: root)
        store.removePreview(outside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testSymlinkIndexLockRejectedWithoutChangingTarget() throws {
        let root = try isolatedRoot()
        let base = root.appendingPathComponent("SikistiriciPreviews-v1")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let target = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent(".sessions.lock"), withDestinationURL: target)
        XCTAssertThrowsError(try PreviewTemporaryStore(temporaryRoot: root))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
    }

    func testConcurrentSessionCreationDoesNotDeleteActivePreviews() throws {
        let root = try isolatedRoot()
        let lock = NSLock()
        var stores: [PreviewTemporaryStore] = []
        var previews: [URL] = []
        var failures: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do {
                let store = try PreviewTemporaryStore(temporaryRoot: root)
                let preview = try store.makePreviewDirectory()
                try Data("keep".utf8).write(to: preview.appendingPathComponent("document.txt"))
                lock.lock(); stores.append(store); previews.append(preview); lock.unlock()
            } catch {
                lock.lock(); failures.append(error); lock.unlock()
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
        XCTAssertEqual(previews.count, 12)
        for preview in previews {
            XCTAssertEqual(try String(contentsOf: preview.appendingPathComponent("document.txt"), encoding: .utf8), "keep")
        }
        withExtendedLifetime(stores) {}
    }

}
