import XCTest
@testable import ArchiveCore

final class ListingTests: XCTestCase {
    func testUnicodeNamesAndEqualsArePreserved() throws {
        let text = "Path = İşler\nFolder = +\nSize = 0\nAttributes = D\n\nPath = İşler/a = b.txt\nFolder = -\nSize = 17\nPacked Size = 10\nEncrypted = +\nAttributes = A\n\n"
        let contents = try ArchiveListing.parse(text)
        XCTAssertEqual(contents.entries.count, 2)
        guard contents.entries.count == 2 else { return }
        XCTAssertTrue(contents.entries[0].isDirectory)
        XCTAssertEqual(contents.entries[1].path, "İşler/a = b.txt")
        XCTAssertEqual(contents.totalSize, 17)
        XCTAssertTrue(contents.entries[1].encrypted)
    }

    func testUnsafePathsAndLinksAreRejected() {
        for path in ["../escape", "/etc/escape", "C:\\escape", "a/../../escape", "a\\..\\escape", "./safe", "a//b"] {
            XCTAssertThrowsError(try SafetyPolicy().validate([ArchiveEntry(path: path)]), path)
        }
        XCTAssertThrowsError(try SafetyPolicy().validate([ArchiveEntry(path: "link", isLink: true)]))
        XCTAssertThrowsError(try SafetyPolicy().validate([ArchiveEntry(path: "link", attributes: "A lrwxrwxrwx")]))
    }

    func testEntryAndExpansionLimitsAreEnforced() {
        XCTAssertThrowsError(try SafetyPolicy(maximumEntries: 1).validate([ArchiveEntry(path: "a"), ArchiveEntry(path: "b")]))
        XCTAssertThrowsError(try SafetyPolicy(maximumExpandedBytes: 10).validate([ArchiveEntry(path: "a", size: 11)]))
        XCTAssertThrowsError(try SafetyPolicy().validate([ArchiveEntry(path: "a", size: -1)]))
        XCTAssertThrowsError(try SafetyPolicy().validate([ArchiveEntry(path: "a"),ArchiveEntry(path: "a")]))
    }

    func testValidNestedPathsAndTurkishNamesPass() throws {
        try SafetyPolicy().validate([ArchiveEntry(path: "Görseller", isDirectory: true), ArchiveEntry(path: "Görseller/çığ şü = $file.png", size: 100)])
    }

    func testLinkMetadataIsRetained() throws {
        let c = try ArchiveListing.parse("Path = escape\nSize = 12\nSymbolic Link = ../../out\nAttributes = A lrwxrwxrwx\n\n")
        XCTAssertEqual(c.entries.first?.isLink, true)
    }
}
