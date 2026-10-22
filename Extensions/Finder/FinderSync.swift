import Cocoa
import FinderSync
import Darwin

@objc(SikistiriciFinderSync)
final class SikistiriciFinderSync: FIFinderSync {
    override init() {
        super.init()
        let home = getpwuid(getuid()).map { URL(fileURLWithPath:String(cString:$0.pointee.pw_dir)) } ?? URL(fileURLWithPath:"/Users")
        FIFinderSyncController.default().directoryURLs = [home,URL(fileURLWithPath:"/Volumes")]
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .toolbarItemMenu,
              let files = FIFinderSyncController.default().selectedItemURLs(), !files.isEmpty else { return nil }
        let menu = NSMenu(title:"Sıkıştırıcı")
        let compress = NSMenuItem(title:"Sıkıştırıcı ile sıkıştır…",action:#selector(compressFiles),keyEquivalent:""); compress.target = self
        menu.addItem(compress)
        let archiveExtensions = Set(["zip","7z","rar","001","tar","gz","xz","bz2","tgz"])
        if files.allSatisfy({ archiveExtensions.contains($0.pathExtension.lowercased()) }) {
            let extract = NSMenuItem(title:"Sıkıştırıcı ile çıkar…",action:#selector(extractFiles),keyEquivalent:""); extract.target = self; menu.addItem(extract)
        }
        return menu
    }
    @objc private func compressFiles() { send(.compress) }
    @objc private func extractFiles() { send(.extract) }
    private func send(_ action: FinderRequest.Action) {
        guard let files = FIFinderSyncController.default().selectedItemURLs(),
              let url = try? FinderRequest(action:action,files:files).encodedURL() else { return }
        NSWorkspace.shared.open(url)
    }
}
