import XCTest
import CArchivePreview
import Darwin
@testable import ArchiveCore

final class PreviewBudgetTests: XCTestCase {
    private func header(name: String, size: Int, type: UInt8 = 48) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int, count: Int) {
            for (index, byte) in text.utf8.prefix(count).enumerated() { bytes[offset + index] = byte }
        }
        put(name, at: 0, count: 100)
        put("0000644", at: 100, count: 7)
        put("0000000", at: 108, count: 7); put("0000000", at: 116, count: 7)
        put(String(format: "%011o", size), at: 124, count: 11)
        put("00000000000", at: 136, count: 11)
        for index in 148..<156 { bytes[index] = 32 }
        bytes[156] = type
        put("ustar", at: 257, count: 5); put("00", at: 263, count: 2)
        let checksum = bytes.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", checksum), at: 148, count: 6)
        bytes[154] = 0; bytes[155] = 32
        return Data(bytes)
    }
    private func archive(names: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewBudget-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let tar = root.appendingPathComponent("names.tar")
        var data = Data()
        for name in names {
            if name.utf8.count > 100 {
                var longName = Data(name.utf8); longName.append(0)
                data.append(header(name: "././@LongLink", size: longName.count, type: 76))
                data.append(longName)
                data.append(Data(repeating: 0, count: (512 - longName.count % 512) % 512))
            }
            data.append(header(name: name, size: 0))
        }
        data.append(Data(repeating: 0, count: 1024)); try data.write(to: tar)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-n", tar.path]; try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return tar.appendingPathExtension("gz")
    }
    func testNativePreviewRejectsOversizedPathBeforeCollectingIt() throws {
        let url = try archive(names: [String(repeating: "a", count: 4097)])
        XCTAssertThrowsError(try NativePreviewReader.list(url)) { error in
            guard case .limit = error as? ArchiveFailure else { return XCTFail("Expected metadata limit, got \(error)") }
        }
    }
    func testNativePreviewRejectsCumulativeNameBudget() throws {
        let names = (0..<1700).map { String(repeating: "a", count: 2590) + "\($0).txt" }
        let url = try archive(names: names)
        XCTAssertThrowsError(try NativePreviewReader.list(url)) { error in
            guard case .limit = error as? ArchiveFailure else { return XCTFail("Expected metadata limit, got \(error)") }
        }
    }
    func testNativeReaderBoundsDecompressedStreamBytes() throws {
        let url = try archive(names: ["one.txt", "two.txt", "three.txt"])
        var message = [CChar](repeating: 0, count: 1024)
        let status = sa_preview_list_bounded(url.path, 100, 4096, 4 * 1024 * 1024, 512,
            { _, _, _, _, _, _ in 1 }, nil, nil, &message, message.count)
        XCTAssertEqual(status, -4)
    }
    func testNativeReaderPollCanStopInputBeforeParsing() throws {
        let url = try archive(names: ["one.txt"])
        var message = [CChar](repeating: 0, count: 1024)
        let status = sa_preview_list_bounded(url.path, 100, 4096, 4 * 1024 * 1024, 64 * 1024 * 1024,
            { _, _, _, _, _, _ in XCTFail("Cancelled reader must not emit entries"); return 1 },
            { _ in 0 }, nil, &message, message.count)
        XCTAssertNotEqual(status, 0)
    }
    func testNativePreviewRejectsNamedPipeWithoutOpeningIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewPipe-\(UUID()).tar")
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try NativePreviewReader.list(url))
    }
    func testSparseLargeZIPListsMetadataWithoutCountingSeeksAsReadBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewSparse-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sparse.zip")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        let name = Data("large.bin".utf8), size: UInt32 = 80 * 1024 * 1024
        func number(_ value: UInt32, bytes: Int) -> Data {
            Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        var local = number(0x04034b50, bytes: 4)
        for value: UInt32 in [20, 0, 0, 0, 0] { local.append(number(value, bytes: 2)) }
        for value: UInt32 in [0, size, size] { local.append(number(value, bytes: 4)) }
        local.append(number(UInt32(name.count), bytes: 2)); local.append(number(0, bytes: 2)); local.append(name)
        try handle.write(contentsOf: local)
        let directoryOffset = UInt32(local.count) + size
        try handle.seek(toOffset: UInt64(directoryOffset))
        var central = number(0x02014b50, bytes: 4)
        for value: UInt32 in [20, 20, 0, 0, 0, 0] { central.append(number(value, bytes: 2)) }
        for value: UInt32 in [0, size, size] { central.append(number(value, bytes: 4)) }
        for value: UInt32 in [UInt32(name.count), 0, 0, 0, 0] { central.append(number(value, bytes: 2)) }
        central.append(number(0, bytes: 4)); central.append(number(0, bytes: 4)); central.append(name)
        try handle.write(contentsOf: central)
        var end = number(0x06054b50, bytes: 4)
        for value: UInt32 in [0, 0, 1, 1] { end.append(number(value, bytes: 2)) }
        end.append(number(UInt32(central.count), bytes: 4)); end.append(number(directoryOffset, bytes: 4)); end.append(number(0, bytes: 2))
        try handle.write(contentsOf: end); try handle.synchronize()
        let contents = try NativePreviewReader.list(url)
        XCTAssertEqual(contents.entries.map(\.path), ["large.bin"])
        XCTAssertEqual(contents.totalSize, Int64(size))
    }
    func testNativePreviewKeepsNormalUnicodeNamesWithinBudget() throws {
        let names = ["Türkçe/çığ-şü.txt", "belgeler/özet.txt"]
        XCTAssertEqual(try NativePreviewReader.list(archive(names: names)).entries.map(\.path), names)
    }
}
