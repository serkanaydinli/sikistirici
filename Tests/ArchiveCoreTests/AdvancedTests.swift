import XCTest
@testable import ArchiveCore

final class AdvancedTests: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciAdvanced-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable: project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func input(_ name: String, data: Data) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }
    func testSplitZIPAnd7zRoundTripAndMissingPartAreExplicit() throws {
        let random = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom"))
        defer { try? random.close() }
        let payload = try XCTUnwrap(random.read(upToCount: 120_000))
        let source = try input("veri.bin", data: payload)
        for format in ArchiveFormat.allCases {
            let result = try engine.create(inputs: [source], destination: root.appendingPathComponent("paket.\(format.rawValue)"), format: format, level: 0, volumeBytes: 40_000)
            XCTAssertGreaterThanOrEqual(result.outputFiles.count, 3)
            let first = try XCTUnwrap(result.outputFiles.first)
            let second = result.outputFiles[1]
            XCTAssertEqual(try VolumeSet.resolve(second), first)
            _ = try engine.extract(second, destination: root.appendingPathComponent("out-\(format.rawValue)"))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("out-\(format.rawValue)/veri.bin")), payload)
            try FileManager.default.removeItem(at: second)
            XCTAssertThrowsError(try engine.list(first)) { error in
                XCTAssertTrue(error.localizedDescription.contains("002"), error.localizedDescription)
            }
        }
    }
    func testMetricsReportRealBytesAndElapsedTime() throws {
        let source = try input("metin.txt", data: Data(repeating: 65, count: 100_000))
        let result = try engine.create(inputs: [source], destination: root.appendingPathComponent("metin.zip"))
        XCTAssertEqual(result.inputBytes, 100_000)
        XCTAssertLessThan(result.bytes, result.inputBytes)
        XCTAssertGreaterThan(result.elapsedSeconds, 0)
        XCTAssertEqual(OperationMetrics.remainingSeconds(fraction: 0.25, elapsed: 10), 30)
        XCTAssertNil(OperationMetrics.remainingSeconds(fraction: 0, elapsed: 10))
        XCTAssertNil(OperationMetrics.remainingSeconds(fraction: 0.01, elapsed: 0.1))
    }
    func testDiskBudgetRejectsBeforeWritingAnyArchive() throws {
        let source = try input("source.txt", data: Data(repeating: 66, count: 2048))
        let lowDisk = ArchiveEngine(executable: engine.executable, capacityProvider: { _ in 1024 })
        XCTAssertThrowsError(try lowDisk.create(inputs: [source], destination: root.appendingPathComponent("no.zip")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("no.zip").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["source.txt"])
    }
    func testRunningCancellationCleansTemporaryOutputAndPreservesExistingFile() throws {
        let random = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom"))
        defer { try? random.close() }
        let source = try input("big.bin", data: try XCTUnwrap(random.read(upToCount: 16_000_000)))
        let existing = try input("keep.7z", data: Data("keep me".utf8))
        let control = OperationControl()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { control.cancel() }
        XCTAssertThrowsError(try engine.create(inputs: [source], destination: existing, format: .sevenZip, level: 9, control: control)) { error in XCTAssertEqual(error as? ArchiveFailure, .cancelled) }
        XCTAssertEqual(try Data(contentsOf: existing), Data("keep me".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".sikistirici") })
    }
}
