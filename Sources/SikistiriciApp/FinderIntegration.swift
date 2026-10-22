import AppKit
import FinderSync
import ArchiveCore

@MainActor
enum FinderIntegration {
    static func showSetup() {
        let alert = NSAlert(); alert.messageText = "Finder ve Quick Look"
        alert.informativeText = "Sağ tık menüsü için macOS Uzantılar bölümünde Sıkıştırıcı Finder’ı etkinleştir. Quick Look önizlemesi için Sıkıştırıcı Önizleme’yi etkinleştir; sonra arşivi seçip boşluk tuşuna bas.\n\nSağ tık > Servisler altında Sıkıştırıcı işlemleri de bulunur. Uzantılar görünmüyorsa uygulamayı Uygulamalar klasörüne taşıyıp yeniden aç. Bu kişisel paket Apple Developer kimliğiyle imzalanmadığından bazı macOS sürümleri uzantıları çalıştırmayabilir."
        alert.addButton(withTitle:"Uzantı ayarlarını aç"); alert.addButton(withTitle:"Tamam")
        if alert.runModal() == .alertFirstButtonReturn { FIFinderSyncController.showExtensionManagementInterface() }
    }
}

extension AppDelegate {
    @objc func compressSelection(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { error.pointee = "Dosya seçimi okunamadı."; return }
        model?.draftInputs = urls; model?.showingCreate = true; NSApp.activate(ignoringOtherApps:true)
    }
    @objc func extractSelection(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { error.pointee = "Arşiv seçimi okunamadı."; return }
        model?.presentBatch(urls,mode:.extract); NSApp.activate(ignoringOtherApps:true)
    }
}
