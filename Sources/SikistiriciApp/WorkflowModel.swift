import SwiftUI
import AppKit
import ArchiveCore

extension AppModel {
    func confirmDraft() -> Bool {
        guard !changes.isEmpty else { return true }
        let alert = NSAlert(); alert.messageText = "Kaydedilmemiş arşiv değişiklikleri var"
        alert.informativeText = "Devam edersen bu değişiklikler bırakılır. Asıl arşiv değiştirilmedi."
        alert.addButton(withTitle: "Düzenlemeye dön"); alert.addButton(withTitle: "Değişiklikleri bırak")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        resetChanges(); return true
    }
    func presentBatch(_ inputs: [URL] = [], mode: BatchMode = .compress) {
        batchInputs = inputs; batchMode = mode; showingBatch = true
    }
    func stageDelete() {
        guard canEdit else { return }
        var candidate = changes; candidate.deletions.formUnion(selection)
        do { _ = try candidate.projectedEntries(entries); recordChanges(candidate,label:"Arşivden sil"); showingEdits = true }
        catch { errorMessage = error.localizedDescription }
    }
    func beginRename() {
        guard canEdit, selection.count == 1, let path = selection.first else { return }
        renamePath = path; renameValue = (path as NSString).lastPathComponent
    }
    func stageRename() {
        guard canEdit, let source = renamePath else { return }
        var candidate = changes
        let parent = (source as NSString).deletingLastPathComponent
        let name = renameValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\") else { errorMessage = "Yeni ad boş olamaz veya yol ayırıcı içeremez."; return }
        let target = parent.isEmpty ? name : parent + "/" + name
        if source == target { renamePath = nil; return }
        candidate.renames[source] = target
        do { _ = try candidate.projectedEntries(entries); recordChanges(candidate,label:"Yeniden adlandır"); renamePath = nil; showingEdits = true }
        catch { errorMessage = error.localizedDescription }
    }
    func stageAddition() {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.title = "Arşive eklenecek dosyalar"; panel.prompt = "Değişikliklere ekle"; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var candidate = changes; candidate.additions += panel.urls
        do { _ = try candidate.projectedEntries(entries); recordChanges(candidate,label:"Dosya ekle"); showingEdits = true }
        catch { errorMessage = error.localizedDescription }
    }
    func saveChanges(asCopy: Bool) {
        guard let archive = archiveURL, !changes.isEmpty, !hasPendingJobs else { return }
        var destination: URL?
        if asCopy {
            let panel = NSSavePanel(); panel.title = "Değişiklikleri farklı kaydet"; panel.nameFieldStringValue = archive.lastPathComponent
            guard panel.runModal() == .OK else { return }; destination = panel.url
        }
        showingEdits = false
        enqueue(.edit(archive,changes,destination,archivePassword,filenameEncoding), title: "Kaydet: \(archive.lastPathComponent)", subtitle: "Arşiv değişiklikleri")
    }
}

