import SwiftUI
import ArchiveCore

struct EncodingSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var encoding: FilenameEncoding
    @State private var preview: [ArchiveEntry]?
    @State private var failure: String?
    @State private var control: OperationControl?
    init(model: AppModel) { self.model = model; _encoding = State(initialValue:model.filenameEncoding) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Dosya adı kodlaması",systemImage:"character.book.closed").font(.title2.bold())
            Text("Eski ZIP dosyalarındaki Türkçe adları kontrol et. Seçim kaynak arşivi değiştirmez; listeleme, önizleme ve çıkarma için kullanılır.").foregroundStyle(.secondary)
            Picker("Kodlama",selection:$encoding) { ForEach(FilenameEncoding.allCases) { Text($0.title).tag($0) } }.pickerStyle(.radioGroup)
            Text("UTF-8 olarak işaretlenmiş adlar korunur. Yanlış kodlanıp kaydedilmiş her ad düzeltilemeyebilir.").font(.caption).foregroundStyle(.secondary)
            if let failure { Label(failure,systemImage:"exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
            if let preview {
                HStack { Text("Önizleme").font(.headline); Spacer(); Text("\(preview.count) öğe").foregroundStyle(.secondary) }
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:7) {
                        ForEach(Array(preview.prefix(200))) { entry in
                            Label(entry.path,systemImage:entry.isDirectory ? "folder":"doc").lineLimit(2).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }.padding(10)
                }.frame(height:250).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))
                if preview.count > 200 { Text("İlk 200 öğe gösteriliyor.").font(.caption).foregroundStyle(.secondary) }
            } else if failure == nil { ProgressView("Dosya adları okunuyor…").frame(maxWidth:.infinity,minHeight:250) }
            HStack {
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Bu kodlamayı kullan") {
                    guard let url = model.archiveURL else { return }
                    model.openArchive(url,password:model.archivePassword,encoding:encoding); dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(preview == nil || model.hasPendingJobs)
            }
        }.padding(28).frame(width:650).tint(Theme.accent)
        .task(id:encoding) { await loadPreview() }
        .onDisappear { control?.cancel() }
    }
    private func loadPreview() async {
        control?.cancel(); let active = OperationControl(); control = active
        preview = nil; failure = nil
        guard let url = model.archiveURL else { return }
        let engine = model.engine; let chosen = encoding; let password = model.archivePassword
        let result = await withTaskCancellationHandler {
            await Task.detached(priority:.userInitiated) { Result { try engine.list(url,password:password,control:active,encoding:chosen) } }.value
        } onCancel: { active.cancel() }
        guard !Task.isCancelled, encoding == chosen else { return }
        switch result { case .success(let contents): preview = contents.entries; case .failure(let error): failure = error.localizedDescription }
    }
}
