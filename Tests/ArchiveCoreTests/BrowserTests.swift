import XCTest
import ArchiveCore
@testable import SikistiriciApp

final class BrowserTests: XCTestCase {
    @MainActor func testSearchChangeClearsInvisibleSelection() {
        let model = AppModel()
        model.entries = [ArchiveEntry(path:"a.txt"),ArchiveEntry(path:"b.txt")]
        model.selection = ["a.txt"]
        model.search = "b"
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.visibleEntries.map(\.path),["b.txt"])
    }
    @MainActor func testMultipleSelectionDoesNotPretendToBeOneFile() {
        let model = AppModel()
        model.entries = [ArchiveEntry(path:"a.txt"),ArchiveEntry(path:"b.txt")]
        model.selection = ["a.txt","b.txt"]
        XCTAssertNil(model.selectedEntry)
    }
    @MainActor func testClosingDismissesPendingPasswordRequest() {
        let model = AppModel()
        model.passwordRequest = PasswordRequest(url:URL(fileURLWithPath:"/old.zip"))
        model.closeArchive()
        XCTAssertNil(model.passwordRequest)
    }
    @MainActor func testUnreadArchiveCannotBeEditedAndFilterClearsSelection() {
        let model = AppModel(); model.archiveURL = URL(fileURLWithPath:"/bad.zip")
        XCTAssertFalse(model.canEdit)
        model.selection = ["a.txt"]; model.category = .images
        XCTAssertTrue(model.selection.isEmpty)
        model.closeArchive(); XCTAssertEqual(model.category,.all)
    }
    func testFolderBrowsingAndGlobalFilterWithNaturalSorting() {
        let entries = [ArchiveEntry(path:"deep/a10.JPG",size:10),ArchiveEntry(path:"deep/a2.jpg",size:20),ArchiveEntry(path:"root.pdf",size:30),ArchiveEntry(path:"empty",isDirectory:true)]
        let root = ArchiveCatalog.visible(entries,directory:"",query:"",category:.all,sort:.name)
        XCTAssertEqual(root.map(\.path),["deep","empty","root.pdf"])
        XCTAssertEqual(ArchiveCatalog.visible(entries,directory:"deep",query:"",category:.all,sort:.name).map(\.path),["deep/a2.jpg","deep/a10.JPG"])
        XCTAssertEqual(ArchiveCatalog.visible(entries,directory:"empty",query:"",category:.images,sort:.largest).map(\.path),["deep/a2.jpg","deep/a10.JPG"])
        XCTAssertEqual(ArchiveCatalog.visible(entries,directory:"",query:"a10",category:.images,sort:.name).map(\.path),["deep/a10.JPG"])
    }
    func testSizesSelectionAndAnalysisDoNotDoubleCountFolders() {
        let entries = [ArchiveEntry(path:"d",size:999,isDirectory:true),ArchiveEntry(path:"d/a.txt",size:10,encrypted:true),ArchiveEntry(path:"d/sub/b.png",size:20),ArchiveEntry(path:"d2/c.txt",size:40)]
        let selected = ArchiveCatalog.selectedFiles(entries,paths:["d","d/a.txt"])
        XCTAssertEqual(selected.count,2)
        XCTAssertEqual(selected.reduce(0) { $0 + $1.size },30)
        let analysis = ArchiveAnalysis(entries:entries)
        XCTAssertEqual(analysis.fileCount,3); XCTAssertEqual(analysis.totalBytes,70)
        XCTAssertEqual(analysis.encryptedCount,1)
        XCTAssertEqual(analysis.largest.first?.path,"d2/c.txt")
        XCTAssertEqual(analysis.groups.first?.category,.documents)
        XCTAssertEqual(analysis.groups.first?.bytes,50)
        XCTAssertTrue(ArchiveAnalysis(entries:[]).groups.isEmpty)
    }
    func testInventoryRoundTripsUnusualNamesAndContainsNoPasswords() throws {
        let path = "çığ/\"=SUM(1,2)\n🎒.txt"
        let data = try ArchiveCatalog.inventory([ArchiveEntry(path:path,size:42,encrypted:true)],archiveName:"şifreli.zip")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(json["schemaVersion"] as? Int,1)
        XCTAssertEqual(json["archive"] as? String,"şifreli.zip")
        let items = try XCTUnwrap(json["entries"] as? [[String:Any]])
        XCTAssertEqual(items[0]["path"] as? String,path)
        XCTAssertEqual(items[0]["bytes"] as? Int,42)
        XCTAssertEqual(Set(items[0].keys),["path","bytes","directory","encrypted"])
    }
    @MainActor func testRevealEntryResetsFiltersAndSelectsCorrectFolder() {
        let model = AppModel(); let entry = ArchiveEntry(path:"bir/iki/çığ.txt",size:16)
        model.entries = [entry]; model.category = .images; model.search = "absent"; model.showingAnalysis = true
        model.revealEntry(entry)
        XCTAssertEqual(model.directory,"bir/iki")
        XCTAssertEqual(model.category,.all); XCTAssertEqual(model.search,"")
        XCTAssertEqual(model.selectedEntry,entry)
        XCTAssertFalse(model.showingAnalysis)
    }
    func testSortModesAndTopTenAreDeterministic() {
        let entries = (1...20).map { ArchiveEntry(path:"file\($0).txt",size:Int64($0)) }
        XCTAssertEqual(ArchiveAnalysis(entries:entries).largest.count,10)
        XCTAssertEqual(ArchiveCatalog.visible(entries,directory:"",query:"",category:.all,sort:.smallest).first?.size,1)
        XCTAssertEqual(ArchiveCatalog.visible(entries,directory:"",query:"",category:.all,sort:.largest).first?.size,20)
        let mixed = [ArchiveEntry(path:"z.txt"),ArchiveEntry(path:"a.zip"),ArchiveEntry(path:"p.jpg")]
        XCTAssertEqual(ArchiveCatalog.visible(mixed,directory:"",query:"",category:.all,sort:.type).map(\.path),["p.jpg","z.txt","a.zip"])
    }
}
