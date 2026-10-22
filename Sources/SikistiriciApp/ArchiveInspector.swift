import SwiftUI
import ArchiveCore

struct ArchiveInspector: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text(model.selection.isEmpty ? "Arşive bakış" : "Seçim ayrıntıları").font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary)
                if let entry = model.selectedEntry {
                    Image(systemName:entry.isDirectory ? "folder.fill" : ArchiveCategory.of(entry).icon)
                        .font(.system(size:34,weight:.light)).foregroundStyle(Theme.accent).frame(width:62,height:62)
                        .background(Theme.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:15))
                    Text(entry.name).font(.system(size:17,weight:.semibold,design:.rounded)).textSelection(.enabled).lineLimit(4)
                    Divider()
                    detail("Tür",entry.isDirectory ? "Klasör" : ArchiveCategory.of(entry).title)
                    detail(entry.isDirectory ? "İçerik boyutu" : "Boyut",AppModel.size(model.selectedBytes))
                    if entry.isDirectory { detail("Dosya","\(model.selectedFiles.count)") }
                    else {
                        detail("Arşivde",entry.packedSize > 0 ? AppModel.size(entry.packedSize) : "—")
                            .help("Sıkıştırılmış boyut motor tarafından bildirilmediğinde çizgi gösterilir.")
                        detail("Şifreli",entry.encrypted ? "Evet" : "Hayır")
                    }
                    Text(entry.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
                    if !entry.isDirectory {
                        Button(action:model.previewSelected) { Label(model.previewLoading ? "Hazırlanıyor…" : "Önizle",systemImage:"eye") }.disabled(model.previewLoading)
                    }
                    selectionActions
                } else if !model.selection.isEmpty {
                    Image(systemName:"doc.on.doc").font(.system(size:34)).foregroundStyle(Theme.accent)
                    Text("\(model.selection.count) öğe seçili").font(.system(size:18,weight:.semibold,design:.rounded))
                    detail("İçerdiği dosya","\(model.selectedFiles.count)")
                    detail("Toplam boyut",AppModel.size(model.selectedBytes))
                    Text("Klasörlerin içindeki dosyalar toplama dahildir.").font(.caption).foregroundStyle(.secondary)
                    selectionActions
                } else {
                    Text(AppModel.size(model.totalSize)).font(.system(size:30,weight:.semibold,design:.rounded)).minimumScaleFactor(0.7).lineLimit(1)
                    Text("\(model.fileCount) dosyanın açılmış boyutu").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(model.analysis.groups) { group in
                        VStack(spacing:7) {
                            HStack(spacing:8) {
                                Image(systemName:group.category.icon).foregroundStyle(Theme.accent).frame(width:17)
                                Text(group.category.title)
                                Spacer()
                                Text(AppModel.size(group.bytes)).foregroundStyle(.secondary).monospacedDigit()
                            }.font(.system(size:11))
                            GeometryReader { geometry in
                                Capsule().fill(Theme.accent.opacity(0.08))
                                Capsule().fill(Theme.accent.opacity(0.7)).frame(width:geometry.size.width * (model.totalSize > 0 ? Double(group.bytes) / Double(model.totalSize) : 0))
                            }.frame(height:4).accessibilityHidden(true)
                        }
                    }
                    Button { model.showingAnalysis = true } label: { Label("Boyutları incele",systemImage:"chart.bar.xaxis") }.disabled(!model.archiveReady)
                    Divider()
                    Text("Bir öğe seçerek önizleyebilir veya yalnız seçtiğin dosyaları çıkarabilirsin.").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).padding(20)
        }.background(Theme.panel)
    }
    private var selectionActions: some View {
        VStack(alignment:.leading,spacing:12) {
            Button { model.showingExtract = true } label: { Label("Seçileni çıkar",systemImage:"arrow.up.doc") }.disabled(!model.archiveReady)
            Button(action:model.copySelectedPaths) { Label("Yolu kopyala",systemImage:"doc.on.clipboard") }.buttonStyle(.borderless).font(.caption)
        }
    }
    private func detail(_ title: String,_ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size:11))
    }
}
