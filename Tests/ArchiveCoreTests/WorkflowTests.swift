import XCTest
@testable import ArchiveCore

final class WorkflowTests: XCTestCase {
    func testBatchOutputsAreSeparateAndSameNamesDoNotCollide() throws {
        let inputs = [URL(fileURLWithPath: "/a/rapor.zip"),URL(fileURLWithPath:"/b/rapor.7z")]
        let jobs = try BatchPlanner.plan(inputs: inputs, destination: URL(fileURLWithPath:"/out"), mode: .extract)
        XCTAssertEqual(jobs.map { $0.destination.lastPathComponent }, ["rapor","rapor (2)"])
        let compressed = try BatchPlanner.plan(inputs: [URL(fileURLWithPath:"/a/One"),URL(fileURLWithPath:"/b/Two")], destination: URL(fileURLWithPath:"/out"), mode:.compress, format:.sevenZip)
        XCTAssertEqual(compressed.map { $0.destination.lastPathComponent }, ["One.7z","Two.7z"])
    }
    func testFinderRouteRoundTripsUnicodeButRefusesRemoteAndUnsupportedCommands() throws {
        let request = FinderRequest(action: .compress, files: [URL(fileURLWithPath:"/tmp/çığ #?.txt")])
        let route = try request.encodedURL()
        XCTAssertEqual(try FinderRequest(url: route).files, request.files)
        XCTAssertThrowsError(try FinderRequest(url: URL(string:"sikistirici://delete?file=file:///tmp/a")!))
        XCTAssertThrowsError(try FinderRequest(url: URL(string:"sikistirici://compress?file=https://example.com/a")!))
        XCTAssertThrowsError(try FinderRequest(url: URL(string:"https://compress?file=file:///tmp/a")!))
    }
}
