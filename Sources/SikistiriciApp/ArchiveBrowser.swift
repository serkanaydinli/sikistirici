import SwiftUI
import ArchiveCore

struct ArchiveBrowser: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            navigation
            searchTools
            Divider()
            if model.inferredFilenameEncoding && !model.loading {
                HStack(spacing:8) {
                    Image(systemName:"character.book.closed")
                    Text("Adlar \(model.filenameEncoding.title) ile okundu · Otomatik tahmin").font(.caption).lineLimit(2)
                    Spacer()
                    Button("Değiştir…") { model.showingEncoding = true }.disabled(model.hasPendingJobs)
                }.foregroundStyle(.secondary).padding(12).background(Theme.accent.opacity(0.06))
                Divider()
            }
            if model.loading {
                VStack(spacing:14) { ProgressView(); Text("Arşiv okunuyor…").foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if !model.archiveReady {
                ContentUnavailableView("Arşiv açılamadı",systemImage:"exclamationmark.triangle",description:Text("Dosyayı veya parolasını kontrol edip yeniden açabilirsin."))
            } else if model.visibleEntries.isEmpty {
                VStack(spacing:12) {
                    ContentUnavailableView(model.globalSearch ? "Eşleşen dosya yok" : "Bu klasör boş",systemImage:model.globalSearch ? "magnifyingglass" : "tray",description:Text(model.globalSearch ? "Arama ve dosya türü filtresini değiştirebilirsin." : "Başka bir klasöre geçebilir veya arşive dosya ekleyebilirsin."))
                    if model.globalSearch { Button("Filtreleri temizle") { model.search = ""; model.category = .all }.padding(.bottom,25) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                Table(model.visibleEntries,selection:$model.selection) {
                    TableColumn("Ad") { entry in
                        HStack(spacing:10) {
                            Image(systemName:entry.isDirectory ? "folder.fill" : ArchiveCategory.of(entry).icon)
                                .foregroundStyle(Theme.accent).font(.system(size:15,weight:.medium)).frame(width:30,height:30).background(Theme.accent.opacity(entry.isDirectory ? 0.12 : 0.055),in:RoundedRectangle(cornerRadius:8))
                            VStack(alignment:.leading,spacing:3) {
                                Text(entry.name).font(.system(size:12,weight:.medium)).lineLimit(1)
                                if model.globalSearch, entry.path != entry.name { Text((entry.path as NSString).deletingLastPathComponent).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            if entry.encrypted { Image(systemName:"lock.fill").font(.system(size:9)).foregroundStyle(.secondary) }
                        }.padding(.vertical,7).contentShape(Rectangle()).help(entry.path).onTapGesture(count:2) {
                            if entry.isDirectory { model.goTo(entry.path) } else { model.selection = [entry.id]; model.previewSelected() }
                        }
                    }.width(min:170)
                    TableColumn("Boyut") { entry in Text(entry.isDirectory ? "—" : AppModel.size(entry.size)).monospacedDigit().foregroundStyle(.secondary) }.width(85)
                    TableColumn("Tür") { entry in Text(entry.isDirectory ? "Klasör" : ((entry.name as NSString).pathExtension.isEmpty ? "Dosya" : (entry.name as NSString).pathExtension.uppercased())).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary) }.width(58)
                }.tableStyle(.inset(alternatesRowBackgrounds:false)).scrollContentBackground(.hidden)
                .contextMenu {
                    Button("Seçileni çıkar…") { model.showingExtract = true }.disabled(model.selection.isEmpty)
                    Button("Önizle",action:model.previewSelected).disabled(model.selectedEntry?.isDirectory != false)
                    Button("Yolları kopyala",action:model.copySelectedPaths).disabled(model.selection.isEmpty)
                    if let entry = model.selectedEntry, model.globalSearch { Button("Bulunduğu klasöre git") { model.revealEntry(entry) } }
                    Divider()
                    Button("Arşive ekle…",action:model.stageAddition).disabled(!model.canEdit)
                    Button("Yeniden adlandır…",action:model.beginRename).disabled(!model.canEdit || model.selection.count != 1)
                    Button("Arşivden sil",role:.destructive,action:model.stageDelete).disabled(!model.canEdit || model.selection.isEmpty)
                }
            }
            Divider()
            HStack(spacing:10) {
                Text(model.selection.isEmpty ? "\(model.visibleEntries.count) öğe" : "\(model.selection.count) seçili · \(AppModel.size(model.selectedBytes))").lineLimit(1)
                Spacer()
                Button(action:model.undoChanges) { Image(systemName:"arrow.uturn.backward") }.buttonStyle(.borderless).disabled(!model.canUndoChanges).help("Arşiv düzenlemesini geri al").accessibilityLabel("Arşiv düzenlemesini geri al")
                Button(action:model.redoChanges) { Image(systemName:"arrow.uturn.forward") }.buttonStyle(.borderless).disabled(!model.canRedoChanges).help("Arşiv düzenlemesini yeniden yap").accessibilityLabel("Arşiv düzenlemesini yeniden yap")
                if !model.changes.isEmpty { Button("Bekleyen değişiklikler") { model.showingEdits = true }.buttonStyle(.borderless) }
            }.font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,16).padding(.vertical,12)
        }
    }
    private var navigation: some View {
        HStack(spacing:10) {
            Button { model.goTo((model.directory as NSString).deletingLastPathComponent) } label: { Image(systemName:"chevron.left") }.disabled(model.directory.isEmpty).help("Üst klasöre git")
            Button { model.goTo("") } label: { Image(systemName:"archivebox") }.buttonStyle(.borderless).help("Arşivin köküne git")
            if model.directory.isEmpty { Text("Arşiv içeriği").font(.system(size:12,weight:.medium)) }
            else {
                Menu {
                    Button("Arşiv kökü") { model.goTo("") }
                    let components = model.directory.split(separator:"/").map(String.init)
                    ForEach(components.indices,id:\.self) { index in
                        Button(components.prefix(index + 1).joined(separator:" / ")) { model.goTo(components.prefix(index + 1).joined(separator:"/")) }
                    }
                } label: { Text(model.directory).lineLimit(1).truncationMode(.middle) }.menuStyle(.borderlessButton).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:5)
            if model.archiveURL?.pathExtension.lowercased() == "zip" {
                Button { model.showingEncoding = true } label: { Label("Kodlama",systemImage:"character.book.closed") }
                    .accessibilityLabel("Dosya adı kodlaması").help("Dosya adı kodlaması: \(model.filenameEncoding.title)").disabled(!model.archiveReady || model.hasPendingJobs)
            }
        }.padding(.horizontal,14).padding(.top,14).padding(.bottom,10)
    }
    private var searchTools: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                HStack(spacing:7) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                    TextField("Tüm arşivde ara",text:$model.search).textFieldStyle(.plain).accessibilityLabel("Arşivde ara")
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Aramayı temizle") }
                }.padding(8).background(Theme.panel,in:RoundedRectangle(cornerRadius:8))
                Picker("Dosya türü",selection:$model.category) { ForEach(ArchiveCategory.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width:114).help("Tüm arşivde dosya türüne göre filtrele")
                Menu { Picker("Sıralama",selection:$model.sort) { ForEach(ArchiveSort.allCases) { Text($0.title).tag($0) } }.pickerStyle(.inline) } label: { Image(systemName:"arrow.up.arrow.down") }.menuStyle(.borderlessButton).frame(width:26).help("Sıralama: \(model.sort.title)").accessibilityLabel("Sıralama")
            }
            if model.globalSearch || model.sort != .name {
                HStack { Text(model.globalSearch ? "Tüm arşivde sonuçlar" : "Bu klasörde"); Spacer(); Text(model.sort.title) }.font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal,14).padding(.bottom,12)
    }
}

struct JobQueueView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.jobs.isEmpty {
                HStack(spacing:10) {
                    Image(systemName:"checkmark.circle").foregroundStyle(Theme.accent)
                    Text("Hazır").font(.system(size:12,weight:.semibold))
                    Text("Yeni bir işlem başlattığında ilerleme burada görünür.").font(.system(size:11)).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
            HStack {
                Label("İş kuyruğu", systemImage: "list.bullet.rectangle").font(.system(size: 12, weight: .semibold))
                if model.hasPendingJobs { Text("Çalışıyor").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                Spacer()
                if !model.jobs.isEmpty { Button("Tamamlananları temizle", action: model.clearFinishedJobs).font(.system(size: 10)).buttonStyle(.borderless) }
            }
            Group {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.jobs) { job in
                            HStack(spacing: 11) {
                                Image(systemName: icon(job.state)).foregroundStyle(color(job.state)).frame(width: 18)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    if job.state == .running {
                                        if let fraction = job.fraction { ProgressView(value: fraction).progressViewStyle(.linear) }
                                        else { ProgressView().progressViewStyle(.linear) }
                                    }
                                    Text(job.detail).font(.system(size: 10)).foregroundStyle(job.state == .failed ? .red : .secondary).lineLimit(2)
                                    JobMetricsView(job:job)
                                }
                                Spacer(minLength: 8)
                                if let output = job.output {
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: { Image(systemName: "folder") }.help("Finder’da göster")
                                }
                                if job.state == .running || job.state == .waiting { Button("İptal") { model.cancel(job.id) }.font(.system(size: 10)) }
                            }
                        }
                    }.padding(.trailing,4)
                }
            }
            }
        }.padding(.horizontal,24).padding(.vertical,12).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func icon(_ state: JobRow.State) -> String { switch state { case .waiting: return "clock"; case .running: return "arrow.triangle.2.circlepath"; case .done: return "checkmark.circle.fill"; case .failed: return "exclamationmark.circle.fill"; case .cancelled: return "xmark.circle" } }
    private func color(_ state: JobRow.State) -> Color { switch state { case .done: return .green; case .failed: return .red; case .running: return Theme.accent; default: return .secondary } }
}

struct JobMetricsView: View {
    let job: JobRow
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) { context in
            let elapsed = (job.finishedAt ?? context.date).timeIntervalSince(job.startedAt ?? context.date)
            HStack(spacing:10) {
                if job.startedAt != nil { Text("Süre: \(duration(elapsed))") }
                if job.state == .running, let left = OperationMetrics.remainingSeconds(fraction:job.fraction,elapsed:elapsed) { Text("Kalan ≈ \(duration(left))") }
                if let outcome = job.outcome, outcome.inputBytes > 0 {
                    Text("\(AppModel.size(outcome.inputBytes)) → \(AppModel.size(outcome.bytes))")
                    if let saving = OperationMetrics.savings(inputBytes:outcome.inputBytes,outputBytes:outcome.bytes), saving != 0 {
                        Text(saving >= 0 ? String(format:"%%%.1f kazanç",saving * 100):String(format:"%%%.1f büyüme",-saving * 100))
                    }
                    if outcome.outputFiles.count > 1 { Text("\(outcome.outputFiles.count) parça") }
                }
            }.font(.system(size:10)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0,Int(seconds)); return value < 60 ? "\(value) sn":"\(value / 60) dk \(value % 60) sn"
    }
}
