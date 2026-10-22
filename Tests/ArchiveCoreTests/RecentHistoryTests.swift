import XCTest
@testable import SikistiriciApp

final class RecentHistoryTests: XCTestCase {
    @MainActor func testRemoveRecentPersistsWithoutDeletingArchiveOrClosingIt() throws {
        let suite = "SikistiriciTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let a = root.appendingPathComponent("a.zip"), b = root.appendingPathComponent("b.zip")
        try Data("unchanged a".utf8).write(to:a); try Data("unchanged b".utf8).write(to:b)
        defaults.set([a.path,b.path],forKey:"recentArchives")
        let model = AppModel(preferences:defaults); model.archiveURL = a
        model.removeRecent(a)
        XCTAssertEqual(model.recent,[b]); XCTAssertEqual(model.archiveURL,a)
        XCTAssertEqual(AppModel(preferences:defaults).recent,[b])
        XCTAssertEqual(try Data(contentsOf:a),Data("unchanged a".utf8))
        XCTAssertEqual(try Data(contentsOf:b),Data("unchanged b".utf8))
    }
    @MainActor func testClearRecentOnlyClearsHistoryPreference() throws {
        let suite = "SikistiriciTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("light",forKey:"appAppearance")
        defaults.set(["/tmp/old.zip"],forKey:"recentArchives")
        let model = AppModel(preferences:defaults)
        model.clearRecent(); model.clearRecent()
        XCTAssertTrue(model.recent.isEmpty)
        XCTAssertNil(defaults.object(forKey:"recentArchives"))
        XCTAssertEqual(defaults.string(forKey:"appAppearance"),"light")
    }
}
