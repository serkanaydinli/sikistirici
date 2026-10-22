import SwiftUI
import AppKit

@main
struct SikistiriciApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Sıkıştırıcı") {
            MainWindow(model: model)
                .onAppear { delegate.model = model; NSApp.applicationIconImage = NSImage(contentsOf:AppResources.url("LauncherIcon","png")) ?? AppResources.icon }
                .onOpenURL { model.receive([$0]) }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Yeni arşiv…", action: model.newArchive).keyboardShortcut("n")
                Button("Arşiv aç…", action: model.chooseArchive).keyboardShortcut("o")
            }
            CommandGroup(replacing:.undoRedo) {
                Button("Geri al",action:model.menuUndo).keyboardShortcut("z").disabled(!model.menuCanUndo)
                Button("Yeniden yap",action:model.menuRedo).keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!model.menuCanRedo)
            }
            CommandMenu("Arşiv") {
                Button("Dosyaları çıkar…") { model.showingExtract = true }.keyboardShortcut("e").disabled(!model.archiveReady)
                Button("Bütünlüğü doğrula", action: model.testArchive).keyboardShortcut("t", modifiers: [.command,.shift]).disabled(!model.archiveReady)
                Button("Önizle", action: model.previewSelected).keyboardShortcut("y").disabled(model.selectedEntry?.isDirectory != false)
                Button("Dosya adı kodlaması…") { model.showingEncoding = true }.disabled(model.archiveURL?.pathExtension.lowercased() != "zip" || model.loading || model.hasPendingJobs)
                Button("Arşiv analizi…") { model.showingAnalysis = true }.keyboardShortcut("i",modifiers:[.command,.shift]).disabled(!model.archiveReady)
                Button("İçerik listesini kaydet…",action:model.exportInventory).disabled(!model.archiveReady)
                Button("Seçili yolları kopyala",action:model.copySelectedPaths).disabled(model.selection.isEmpty)
                Divider()
                Button("Toplu işlem…") { model.presentBatch() }.keyboardShortcut("b",modifiers:[.command,.shift])
                Button("Arşive dosya ekle…",action:model.stageAddition).disabled(!model.canEdit)
                Button("Yeniden adlandır…",action:model.beginRename).disabled(!model.canEdit || model.selection.count != 1)
                Button("Arşivden sil",action:model.stageDelete).disabled(!model.canEdit || model.selection.isEmpty)
                Button("Değişiklikleri gözden geçir…") { model.showingEdits = true }.keyboardShortcut("s").disabled(model.changes.isEmpty)
                Divider()
                Button("Arşivi kapat", action: model.closeArchive).disabled(model.archiveURL == nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); NSApp.servicesProvider = self; NSUpdateDynamicServices() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationPending { return .terminateLater }
        guard model?.confirmDraft() != false else { return .terminateCancel }
        if model?.hasPendingJobs == true {
            let alert = NSAlert(); alert.messageText = "Devam eden işler var"
            alert.informativeText = "Devam eden işler iptal edilir. Çıkış, işlemler ve hedefteki değişikliklerin geri alınması tamamlanana kadar bekler."
            alert.addButton(withTitle: "Çalışmaya devam et"); alert.addButton(withTitle: "İptal et ve çık")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        guard let model else { return .terminateNow }
        terminationPending = true
        Task { @MainActor in
            await model.cancelAndWaitForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
