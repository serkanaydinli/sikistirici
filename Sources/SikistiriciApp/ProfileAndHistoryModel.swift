import SwiftUI
import AppKit
import ArchiveCore

extension AppModel {
    var canUndoChanges: Bool { canEdit && editHistory.canUndo }
    var canRedoChanges: Bool { canEdit && editHistory.canRedo }
    func recordChanges(_ candidate: ArchiveChanges, label: String) {
        editHistory.record(candidate,label:label); changes = editHistory.current
    }
    func resetChanges() { changes = ArchiveChanges(); editHistory.reset() }
    func discardChanges() {
        guard canEdit else { return }
        recordChanges(ArchiveChanges(),label:"Tüm değişiklikleri bırak")
    }
    func undoChanges() { guard canUndoChanges else { return }; changes = editHistory.undo() }
    func redoChanges() { guard canRedoChanges else { return }; changes = editHistory.redo() }
    // Keep the standard text editor's undo stack when a text field has focus.
    var focusedTextEditor: NSTextView? { NSApp?.keyWindow?.firstResponder as? NSTextView }
    var menuCanUndo: Bool { focusedTextEditor.map { $0.undoManager?.canUndo ?? false } ?? canUndoChanges }
    var menuCanRedo: Bool { focusedTextEditor.map { $0.undoManager?.canRedo ?? false } ?? canRedoChanges }
    func menuUndo() { if let editor = focusedTextEditor { editor.undoManager?.undo() } else { undoChanges() } }
    func menuRedo() { if let editor = focusedTextEditor { editor.undoManager?.redo() } else { redoChanges() } }
    func saveProfile(_ profile: ArchiveProfile) throws {
        var candidate = profiles
        if let index = candidate.firstIndex(where:{ $0.id == profile.id }) { candidate[index] = profile }
        else { candidate.append(profile) }
        try ProfileStorage.save(candidate); profiles = candidate
    }
    func deleteProfile(_ id: UUID) throws {
        let candidate = profiles.filter { $0.id != id }
        try ProfileStorage.save(candidate); profiles = candidate
    }
}
