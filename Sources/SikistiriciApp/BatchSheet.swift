import SwiftUI
import AppKit
import ArchiveCore

struct BatchSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ArchiveFormat = .zip
    @State private var password = ""
    @State private var destination: URL?
    @State private var clean = true
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Toplu işlem", systemImage: "square.stack.3d.up").font(.system(size: 24,weight:.bold,design:.rounded))
            Picker("İşlem",selection:$model.batchMode) { Text("Ayrı ayrı sıkıştır").tag(BatchMode.compress); Text("Ayrı klasörlere çıkar").tag(BatchMode.extract) }.pickerStyle(.segmented)
            HStack { Text("\(model.batchInputs.count) kaynak").font(.headline); Spacer(); Button("Dosya / klasör ekle…",action:add) }
            ScrollView {
                VStack(alignment:.leading,spacing:9) {
                    if model.batchInputs.isEmpty { Text("Her kaynak kendi işi ve kendi çıktısı olur.").foregroundStyle(.secondary).padding(.vertical,20) }
                    ForEach(model.batchInputs,id:\.path) { file in HStack { Image(systemName:"doc.zipper"); Text(file.lastPathComponent).lineLimit(1); Spacer(); Button { model.batchInputs.removeAll { $0 == file } } label:{ Image(systemName:"xmark.circle.fill") }.buttonStyle(.borderless) }.help(file.path) }
                }.padding(12)
            }.frame(height:150).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:10))
            if model.batchMode == .compress {
                Picker("Biçim",selection:$format) { ForEach(ArchiveFormat.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Toggle(".DS_Store ve __MACOSX girdilerini dışla",isOn:$clean)
                if format == .sevenZip { SecureField("Ortak parola (isteğe bağlı)",text:$password) }
            } else {
                SecureField("Ortak parola (gerekiyorsa)",text:$password)
                Text("Her arşiv ayrı bir klasöre çıkarılır. Aynı adlar numaralandırılır; mevcut klasörler korunur.").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text(destination?.path ?? "Çıktı klasörü seçilmedi").font(.caption).lineLimit(2); Spacer(); Button("Konum seç…",action:chooseDestination) }
            if let destination, let free = try? DiskBudget.available(at:destination) { Text("Hedefte \(AppModel.size(free)) boş · Her iş başlamadan alan denetlenir").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack { Text("Bir işte hata olursa sıradaki devam eder.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Vazgeç") { dismiss() }; Button("Kuyruğa ekle",action:start).buttonStyle(.borderedProminent).disabled(model.batchInputs.isEmpty || destination == nil) }
        }.padding(28).frame(width:600).tint(Theme.accent)
    }
    private func add() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = model.batchMode == .compress
        if panel.runModal() == .OK { for url in panel.urls where !model.batchInputs.contains(url) { model.batchInputs.append(url) } }
    }
    private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK { destination = panel.url }
    }
    private func start() {
        guard let destination else { return }
        do {
            let items = try BatchPlanner.plan(inputs:model.batchInputs,destination:destination,mode:model.batchMode,format:format)
            for item in items {
                if model.batchMode == .compress { model.enqueue(.create([item.source],item.destination,format,5,format == .sevenZip && !password.isEmpty ? password:nil,clean),title:"Sıkıştır: \(item.source.lastPathComponent)",subtitle:item.destination.path) }
                else { model.enqueue(.extract(item.source,item.destination,nil,password.isEmpty ? nil:password,.rename),title:"Çıkar: \(item.source.lastPathComponent)",subtitle:item.destination.path) }
            }
            password = ""; dismiss()
        } catch { model.errorMessage = error.localizedDescription }
    }
}
