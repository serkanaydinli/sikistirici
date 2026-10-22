import SwiftUI
import ArchiveCore
import UniformTypeIdentifiers

extension AppModel {
    func revealEntry(_ entry: ArchiveEntry) {
        goTo((entry.path as NSString).deletingLastPathComponent)
        selection = [entry.path]; showingAnalysis = false
    }
    func exportInventory() {
        guard let url = archiveURL, archiveReady else { return }
        let panel = NSSavePanel(); panel.title = "Arşiv içerik listesini kaydet"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "-icerik.json"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try ArchiveCatalog.inventory(entries,archiveName:url.lastPathComponent).write(to:target,options:.atomic)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch { errorMessage = error.localizedDescription }
    }
    func copySelectedPaths() {
        guard !selection.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.sorted().joined(separator:"\n"),forType:.string)
    }
}

struct ArchiveInsights: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Label("Arşiv analizi",systemImage:"chart.bar.xaxis").font(.system(size:24,weight:.bold,design:.rounded))
                    Text(model.archiveURL?.lastPathComponent ?? "").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing:12) {
                InsightMetric(title:"DOSYA",value:"\(model.fileCount)",icon:"doc.on.doc")
                InsightMetric(title:"AÇILMIŞ BOYUT",value:AppModel.size(model.totalSize),icon:"externaldrive")
                InsightMetric(title:"ŞİFRELİ DOSYA",value:"\(model.analysis.encryptedCount)",icon:"lock")
            }
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:14) {
                        Text("Neler yer kaplıyor?").font(.headline)
                        if model.analysis.groups.isEmpty { Text("Bu arşivde dosya yok.").foregroundStyle(.secondary) }
                        ForEach(model.analysis.groups) { group in
                            VStack(spacing:6) {
                                HStack {
                                    Label(group.category.title,systemImage:group.category.icon)
                                    Text("\(group.count) dosya").foregroundStyle(.secondary)
                                    Spacer()
                                    Text(AppModel.size(group.bytes)).monospacedDigit()
                                }.font(.callout)
                                GeometryReader { geometry in
                                    Capsule().fill(Theme.accent.opacity(0.12))
                                    Capsule().fill(Theme.accent).frame(width:geometry.size.width * (model.totalSize > 0 ? Double(group.bytes) / Double(model.totalSize) : 0))
                                }.frame(height:6).accessibilityLabel("\(group.category.title): \(AppModel.size(group.bytes))")
                            }
                        }
                    }
                    VStack(alignment:.leading,spacing:10) {
                        HStack { Text("En büyük dosyalar").font(.headline); Spacer(); Text("İlk 10 · Listede bulmak için tıkla").font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(model.analysis.largest.enumerated()),id:\.element.id) { index,entry in
                            Button { model.revealEntry(entry) } label: {
                                HStack(spacing:12) {
                                    Text(String(format:"%02d",index + 1)).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary).frame(width:24)
                                    Image(systemName:ArchiveCategory.of(entry).icon).foregroundStyle(Theme.accent).frame(width:20)
                                    VStack(alignment:.leading,spacing:3) { Text(entry.name).lineLimit(1); Text(entry.path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer()
                                    Text(AppModel.size(entry.size)).monospacedDigit().foregroundStyle(.secondary)
                                    Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(10).background(Theme.panel,in:RoundedRectangle(cornerRadius:9)).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(entry.path)
                        }
                    }
                }.padding(.trailing,6)
            }
            HStack {
                Text("Boyutlar arşivde kayıtlı açılmış boyutlardır.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("İçerik listesini kaydet…",action:model.exportInventory)
            }
        }.padding(26).frame(width:690,height:650).background(Theme.canvas).tint(Theme.accent)
    }
}

struct InsightMetric: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Label(title,systemImage:icon).font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size:23,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(Theme.panel,in:RoundedRectangle(cornerRadius:12))
    }
}
