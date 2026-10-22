import XCTest
@testable import ArchiveCore
@testable import SikistiriciApp

final class V03Tests: XCTestCase {
    var root: URL!
    var engine: ArchiveEngine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciV03-\(UUID())")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let package = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        engine = ArchiveEngine(executable:package.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func file(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(text.utf8).write(to:url); return url
    }
    // Original synthetic ZIP fixture: stored entries, explicit raw filename bytes, no third-party data.
    func zip(_ names: [[UInt8]], flags: UInt16 = 0, corruptCRC: Bool = false) throws -> URL {
        var data = Data(); var central = Data()
        func add(_ n: UInt32, _ bytes: Int, to d: inout Data) { for i in 0..<bytes { d.append(UInt8(truncatingIfNeeded:n >> (i * 8))) } }
        let payload = Data("Türkçe içerik".utf8)
        var crc: UInt32 = 0xffffffff
        for byte in payload { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320:0) } }
        crc ^= 0xffffffff; if corruptCRC { crc ^= 1 }
        for name in names {
            let offset = UInt32(data.count)
            for (n,b) in [(UInt32(0x04034b50),4),(20,2),(UInt32(flags),2),(0,2),(0,2),(33,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(name.count),2),(0,2)] { add(n,b,to:&data) }
            data.append(contentsOf:name); data.append(payload)
            for (n,b) in [(UInt32(0x02014b50),4),(20,2),(20,2),(UInt32(flags),2),(0,2),(0,2),(33,2),(crc,4),(UInt32(payload.count),4),(UInt32(payload.count),4),(UInt32(name.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)] { add(n,b,to:&central) }
            central.append(contentsOf:name)
        }
        let offset = data.count; data.append(central)
        for (n,b) in [(UInt32(0x06054b50),4),(0,2),(0,2),(UInt32(names.count),2),(UInt32(names.count),2),(UInt32(central.count),4),(UInt32(offset),4),(0,2)] { add(n,b,to:&data) }
        let url = root.appendingPathComponent("\(UUID()).zip"); try data.write(to:url); return url
    }
    func testTurkishLegacyEncodingsListExtractAndEditUsingSameNames() throws {
        let samples: [(FilenameEncoding,[UInt8])] = [(.windowsTurkish,[0xe7,0xfd,0xf0,0x2d,0xfe,0xfc]),(.dosTurkish,[0x87,0x8d,0xa7,0x2d,0x9f,0x81])]
        for (encoding,raw) in samples {
            let archive = try zip([raw + Array(".txt".utf8)])
            XCTAssertEqual(try engine.list(archive,encoding:encoding).entries.map(\.path),["çığ-şü.txt"])
            let out = root.appendingPathComponent(encoding.rawValue)
            _ = try engine.extract(archive,destination:out,selected:["çığ-şü.txt"],encoding:encoding)
            XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("çığ-şü.txt"),encoding:.utf8),"Türkçe içerik")
            _ = try engine.saveEdits(archive,changes:ArchiveChanges(renames:["çığ-şü.txt":"doğru.txt"]),encoding:encoding)
            XCTAssertEqual(try engine.list(archive).entries.map(\.path),["doğru.txt"])
        }
    }
    func testExplicitEncodingPreservesUTF8FlaggedNames() throws {
        let archive = try zip([Array("şifre-🎒.txt".utf8)],flags:0x800)
        for encoding in [FilenameEncoding.windowsTurkish,.dosTurkish,.utf8] {
            XCTAssertEqual(try engine.list(archive,encoding:encoding).entries.first?.path,"şifre-🎒.txt")
        }
    }
    func testAutomaticOpenRepairsTurkishNamesAndExtractsWithoutManualChoice() throws {
        for raw in [[UInt8](arrayLiteral:0xe7,0xfd,0xf0,0x2d,0xfe,0xfc),[0x87,0x8d,0xa7,0x2d,0x9f,0x81]] {
            let archive = try zip([raw + Array(".txt".utf8)])
            XCTAssertEqual(try engine.list(archive).entries.map(\.path),["çığ-şü.txt"])
            let out = root.appendingPathComponent(UUID().uuidString)
            _ = try engine.extract(archive,destination:out,selected:["çığ-şü.txt"])
            XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("çığ-şü.txt"),encoding:.utf8),"Türkçe içerik")
        }
    }
    func testAutomaticEncodingLeavesUnicodeAndSourceBytesUnchanged() throws {
        for name in ["Türkçe-🎒.txt","gerçek-\u{efe7}.txt"] {
            let archive = try zip([Array(name.utf8)],flags:0x800)
            let before = try Data(contentsOf:archive)
            XCTAssertEqual(try engine.read(archive).contents.entries.first?.path,name)
            _ = try engine.extract(archive,destination:root.appendingPathComponent(UUID().uuidString))
            XCTAssertEqual(try Data(contentsOf:archive),before)
        }
    }
    @MainActor func testAppAutomaticOpenPublishesResolvedEncoding() async throws {
        let archive = try zip([[0xe7,0xfd,0xf0] + Array(".txt".utf8)])
        let model = AppModel(); model.openArchive(archive)
        for _ in 0..<150 where model.loading { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.entries.first?.path,"çığ.txt")
        XCTAssertEqual(model.filenameEncoding,.windowsTurkish)
        XCTAssertTrue(model.inferredFilenameEncoding)
        model.closeArchive(); XCTAssertFalse(model.inferredFilenameEncoding)
    }
    func testEncodedZIPRejectsTraversalCollisionsAndExpansionLimit() throws {
        let traversal = try zip([Array("../escape.txt".utf8)])
        XCTAssertThrowsError(try engine.extract(traversal,destination:root.appendingPathComponent("unsafe"),encoding:.windowsTurkish))
        let duplicates = try zip([Array("same.txt".utf8),Array("SAME.TXT".utf8)])
        XCTAssertThrowsError(try engine.list(duplicates,encoding:.windowsTurkish))
        let archive = try zip([Array("safe.txt".utf8)])
        let limited = ArchiveEngine(executable:engine.executable,safety:SafetyPolicy(maximumExpandedBytes:2))
        XCTAssertThrowsError(try limited.extract(archive,destination:root.appendingPathComponent("limit"),encoding:.windowsTurkish))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("escape.txt").path))
    }
    func testEncodedZIPCRCFailureNeverPublishesAndCancellationWorks() throws {
        let bad = try zip([Array("safe.txt".utf8)],corruptCRC:true)
        let out = root.appendingPathComponent("bad")
        XCTAssertThrowsError(try engine.extract(bad,destination:out,encoding:.windowsTurkish))
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.appendingPathComponent("safe.txt").path))
        let cancel = OperationControl(); cancel.cancel()
        XCTAssertThrowsError(try engine.list(bad,control:cancel,encoding:.windowsTurkish))
    }
    func testEncodedZIPSelectedNestedFileDoesNotExtractSibling() throws {
        let archive = try zip([Array("docs/one.txt".utf8),Array("docs/two.txt".utf8)])
        let out = root.appendingPathComponent("selected")
        _ = try engine.extract(archive,destination:out,selected:["docs/one.txt"],encoding:.windowsTurkish)
        XCTAssertTrue(FileManager.default.fileExists(atPath:out.appendingPathComponent("docs/one.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.appendingPathComponent("docs/two.txt").path))
    }
    func testEncodedEncryptedZIPUsesOnlySuppliedPassword() throws {
        let source = try file("secret.txt","Gizli")
        let archive = root.appendingPathComponent("encrypted.zip")
        _ = try EngineProcess(executable:engine.executable).run(["a","-tzip","-mem=AES256","-p","-sccUTF-8","--",archive.path,source.path],password:"deneme-password",creatingPassword:true,control:OperationControl())
        let out = root.appendingPathComponent("private")
        XCTAssertThrowsError(try engine.extract(archive,destination:out,password:"wrong",encoding:.windowsTurkish))
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.appendingPathComponent("secret.txt").path))
        _ = try engine.extract(archive,destination:out,password:"deneme-password",encoding:.windowsTurkish)
        XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("secret.txt"),encoding:.utf8),"Gizli")
    }
    func testCreationFiltersKeepStructureExcludeAncestorsAndMatchPreview() throws {
        _ = try file("Project/docs/rapor.PDF","keep")
        _ = try file("Project/docs/small.pdf","")
        _ = try file("Project/node_modules/pkg/secret.pdf","exclude")
        _ = try file("Project/.git/info.pdf","exclude")
        _ = try file("Project/docs/readme.txt","exclude")
        _ = try file("Project/.DS_Store","exclude")
        let inputs = [root.appendingPathComponent("Project")]
        let rule = ArchiveFilter(excludedNames:["node_modules",".git"],includedExtensions:["pdf"],pathContains:"docs",minimumBytes:1,maximumBytes:10)
        let plan = try CreationPlan.build(inputs:inputs,filter:rule,cleanMetadata:true)
        XCTAssertEqual(plan.files.map(\.path),["Project/docs/rapor.PDF"])
        XCTAssertEqual(plan.excludedPaths.count,5)
        for format in ArchiveFormat.allCases {
            let result = try engine.create(inputs:inputs,destination:root.appendingPathComponent("filter.\(format.rawValue)"),format:format,cleanMetadata:true,filter:rule)
            XCTAssertEqual(try engine.list(result.url).entries.filter { !$0.isDirectory }.map(\.path),plan.files.map(\.path))
            XCTAssertEqual(result.skippedCount,5)
        }
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("Project/node_modules/pkg/secret.pdf"),encoding:.utf8),"exclude")
    }
    func testEmptyFiltersAndSymlinksFailBeforeOutputAndInvalidRulesFail() throws {
        let source = try file("source/a.txt","A")
        XCTAssertThrowsError(try engine.create(inputs:[source],destination:root.appendingPathComponent("empty.zip"),filter:ArchiveFilter(includedExtensions:["pdf"])))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("empty.zip").path))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("source/link.txt"),withDestinationURL:source)
        XCTAssertThrowsError(try CreationPlan.build(inputs:[source.deletingLastPathComponent()],filter:ArchiveFilter(excludedNames:["link.txt"]),cleanMetadata:false))
        XCTAssertThrowsError(try ArchiveFilter(minimumBytes:10,maximumBytes:2).validate())
        XCTAssertThrowsError(try ArchiveFilter(excludedNames:["*.txt"]).validate())
    }
    func testFilteredArchivePreservesPrivateDirectoryPermissions() throws {
        _ = try file("private/file.txt","gizli")
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.appendingPathComponent("private").path)
        let result = try engine.create(inputs:[root.appendingPathComponent("private")],destination:root.appendingPathComponent("permissions.zip"),filter:ArchiveFilter(includedExtensions:["txt"]))
        let out = root.appendingPathComponent("permissions-out")
        _ = try engine.extract(result.url,destination:out)
        let mode = try FileManager.default.attributesOfItem(atPath:out.appendingPathComponent("private").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue,0o700)
    }
    func testProfilesPersistUpdateDeleteWithoutPasswords() throws {
        let name = "SikistiriciV03Tests.\(UUID())"; let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        var profile = ArchiveProfile(name:"Proje gönder",format:.sevenZip,level:7,cleanMetadata:true,volumeBytes:104_857_600,destinationFolder:root.path,filter:ArchiveFilter(excludedNames:[".git"]))
        try ProfileStorage.save([profile],to:defaults)
        XCTAssertEqual(try ProfileStorage.load(from:defaults),[profile])
        let encoded = String(data:try JSONEncoder().encode(profile),encoding:.utf8)!
        XCTAssertFalse(encoded.lowercased().contains("password"))
        profile.level = 1; try ProfileStorage.save([profile],to:defaults)
        XCTAssertEqual(try ProfileStorage.load(from:defaults).first?.level,1)
        XCTAssertThrowsError(try ProfileStorage.save([profile,ArchiveProfile(name:"proje gönder")],to:defaults))
        try ProfileStorage.save([],to:defaults); XCTAssertTrue(try ProfileStorage.load(from:defaults).isEmpty)
    }
    func testHistoryBranchingAndDiscardAreReversible() {
        var history = EditHistory()
        let renamed = ArchiveChanges(renames:["a.txt":"b.txt"])
        let deleted = ArchiveChanges(deletions:["c.txt"],renames:renamed.renames)
        history.record(renamed,label:"Rename"); history.record(deleted,label:"Delete")
        XCTAssertEqual(history.undo(),renamed); XCTAssertEqual(history.undo(),ArchiveChanges())
        XCTAssertEqual(history.redo(),renamed)
        history.record(ArchiveChanges(),label:"Discard")
        XCTAssertFalse(history.canRedo); XCTAssertEqual(history.undo(),renamed)
        history.reset(); XCTAssertFalse(history.canUndo); XCTAssertFalse(history.canRedo)
    }
    @MainActor func testAppHistoryResetsOnArchiveCloseAndLocksDuringJobs() {
        let model = AppModel(); model.archiveURL = root.appendingPathComponent("draft.zip")
        model.archiveReady = true; model.entries = [ArchiveEntry(path:"a.txt"),ArchiveEntry(path:"b.txt")]
        model.selection = ["a.txt"]; model.stageDelete()
        XCTAssertTrue(model.canUndoChanges)
        model.undoChanges(); XCTAssertTrue(model.changes.isEmpty); XCTAssertTrue(model.canRedoChanges)
        model.jobs = [JobRow(id:UUID(),title:"test",subtitle:"",state:.waiting)]
        XCTAssertFalse(model.canRedoChanges)
        model.jobs = []; model.closeArchive()
        XCTAssertFalse(model.editHistory.canUndo); XCTAssertFalse(model.editHistory.canRedo)
    }
    @MainActor func testQueuedExtractionKeepsEncodingAfterCurrentArchiveChanges() async throws {
        let archive = try zip([[0xe7,0xfd,0xf0] + Array(".txt".utf8)])
        let out = root.appendingPathComponent("queued")
        let model = AppModel(); model.filenameEncoding = .windowsTurkish
        model.enqueue(.extract(archive,out,nil,nil,.rename,model.filenameEncoding),title:"Kodlama",subtitle:"")
        model.filenameEncoding = .automatic
        for _ in 0..<150 where model.hasPendingJobs { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(model.hasPendingJobs)
        XCTAssertEqual(model.jobs.first?.state,.done)
        XCTAssertEqual(try String(contentsOf:out.appendingPathComponent("çığ.txt"),encoding:.utf8),"Türkçe içerik")
    }
}
