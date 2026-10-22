import SwiftUI
import ArchiveCore

struct EditorSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Bekleyen değişiklikler",systemImage:"pencil.and.list.clipboard").font(.system(size:23,weight:.bold,design:.rounded))
            Text("Asıl arşiv Kaydet’e basana kadar değişmez. Yeni arşiv doğrulandıktan sonra kaydedilir.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Geri al",systemImage:"arrow.uturn.backward",action:model.undoChanges).disabled(!model.canUndoChanges)
                Button("Yeniden yap",systemImage:"arrow.uturn.forward",action:model.redoChanges).disabled(!model.canRedoChanges)
                Text("Kaydedilmemiş düzenlemeler için").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    ForEach(model.changes.deletions.sorted(),id:\.self) { path in Label("Sil: \(path)",systemImage:"minus.circle").foregroundStyle(.red) }
                    ForEach(model.changes.renames.keys.sorted(),id:\.self) { path in Label("\(path) → \(model.changes.renames[path] ?? "")",systemImage:"pencil").foregroundStyle(.orange) }
                    ForEach(model.changes.additions,id:\.path) { url in Label("Ekle: \(url.lastPathComponent)",systemImage:"plus.circle").foregroundStyle(.green) }
                }.font(.system(size:13)).padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }.frame(height:170).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:10))
            if let projected = try? model.changes.projectedEntries(model.entries) { Text("Kaydedilince \(projected.filter { !$0.isDirectory }.count) dosya · \(AppModel.size(projected.reduce(0) { $0 + $1.size }))").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Tümünü bırak",role:.destructive) { model.discardChanges(); model.showingEdits = false }
                Spacer(); Button("Düzenlemeye dön") { model.showingEdits = false }
                Button("Farklı kaydet…") { model.saveChanges(asCopy:true) }.disabled(model.hasPendingJobs || model.changes.isEmpty)
                Button("Kaydet") { model.saveChanges(asCopy:false) }.buttonStyle(.borderedProminent).disabled(model.hasPendingJobs || model.changes.isEmpty)
            }
        }.padding(28).frame(width:680).tint(Theme.accent)
    }
}

struct RenameSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Yeniden adlandır").font(.title2.bold())
            Text(model.renamePath ?? "").font(.caption).foregroundStyle(.secondary)
            TextField("Yeni ad",text:$model.renameValue).textFieldStyle(.roundedBorder).onSubmit(model.stageRename)
            HStack { Spacer(); Button("Vazgeç") { model.renamePath = nil }; Button("Değişikliğe ekle",action:model.stageRename).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:450)
    }
}
