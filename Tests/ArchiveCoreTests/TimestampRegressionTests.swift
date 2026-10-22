import XCTest
import Darwin
@testable import ArchiveCore

final class TimestampRegressionTests: XCTestCase {
    func testMissingModificationTimeDoesNotInventEpochAndNanosecondsArePreserved() throws {
        XCTAssertNil(FileModificationTime(isSet:false,seconds:0,nanoseconds:0))
        XCTAssertNotNil(FileModificationTime(isSet:true,seconds:0,nanoseconds:0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to:url); defer { try? FileManager.default.removeItem(at:url) }
        let before = try FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as? Date
        try FileModificationTime(isSet:false,seconds:0,nanoseconds:0)?.apply(to:url)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as? Date,before)
        try FileModificationTime(isSet:true,seconds:999_999_999,nanoseconds:123_456_700)?.apply(to:url)
        var info = stat(); XCTAssertEqual(lstat(url.path,&info),0)
        XCTAssertEqual(info.st_mtimespec.tv_sec,999_999_999)
        XCTAssertEqual(info.st_mtimespec.tv_nsec,123_456_700)
    }
    func testEncodedZIPPreservesFilesAndDirectoryDatesAcrossEncodings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let package = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine = ArchiveEngine(executable:package.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
        let archive = root.appendingPathComponent("dated.zip")
        let script = """
        import zipfile,sys,struct
        with zipfile.ZipFile(sys.argv[1], 'w') as z:
            for name,body,mode in [('docs/',b'',0o40750),('docs/file.txt',b'payload',0o100640)]:
                i=zipfile.ZipInfo(name,(2001,9,9,1,46,40)); i.create_system=3; i.external_attr=mode<<16
                stamp=(999999999+11644473600)*10000000+1234567
                i.extra=struct.pack("<HHIHHQQQ",10,32,0,1,24,stamp,stamp,stamp)
                z.writestr(i,body)
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/python3"); process.arguments = ["-c",script,archive.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        var baseline: [String:Date] = [:]
        for encoding in [FilenameEncoding.automatic,.utf8,.windowsTurkish,.dosTurkish] {
            let out = root.appendingPathComponent(encoding.rawValue)
            _ = try engine.extract(archive,destination:out,encoding:encoding)
            for path in ["docs/file.txt","docs"] {
                let attributes = try FileManager.default.attributesOfItem(atPath:out.appendingPathComponent(path).path)
                let date = try XCTUnwrap(attributes[.modificationDate] as? Date)
                if encoding == .automatic { baseline[path] = date }
                XCTAssertEqual(date.timeIntervalSince1970,try XCTUnwrap(baseline["docs/file.txt"]).timeIntervalSince1970,accuracy:1)
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue,path == "docs" ? 0o750:0o640)
                var info = stat(); XCTAssertEqual(lstat(out.appendingPathComponent(path).path,&info),0)
                XCTAssertEqual(info.st_mtimespec.tv_sec,999_999_999)
                XCTAssertEqual(info.st_mtimespec.tv_nsec,123_456_700,"\(encoding.rawValue): \(path)")
            }
        }
        // Replace equal-length ASCII bytes in local + central ZIP names to model legacy archives.
        let original = try Data(contentsOf:archive)
        for (encoding,raw) in [(FilenameEncoding.windowsTurkish,[UInt8(0xe7),0xfd,0xf0]),(.dosTurkish,[UInt8(0x87),0x8d,0xa7])] {
            var bytes = original
            let old = Data("file.txt".utf8), new = Data(raw + Array("-.txt".utf8))
            while let range = bytes.range(of:old) { bytes.replaceSubrange(range,with:new) }
            let legacy = root.appendingPathComponent(encoding.rawValue + ".zip"); try bytes.write(to:legacy)
            for selection in [encoding,.automatic] {
                let out = root.appendingPathComponent(encoding.rawValue + selection.rawValue)
                _ = try engine.extract(legacy,destination:out,encoding:selection)
                let file = out.appendingPathComponent("docs/çığ-.txt")
                XCTAssertEqual(try Data(contentsOf:file),Data("payload".utf8))
                var info = stat(); XCTAssertEqual(lstat(file.path,&info),0)
                XCTAssertEqual(info.st_mtimespec.tv_sec,999_999_999)
                XCTAssertEqual(info.st_mtimespec.tv_nsec,123_456_700)
            }
        }
    }
}
