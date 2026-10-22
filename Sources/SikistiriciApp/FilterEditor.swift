import SwiftUI
import ArchiveCore

struct FilterEditor: View {
    @Binding var excluded: String
    @Binding var extensions: String
    @Binding var pathContains: String
    @Binding var minimumMB: String
    @Binding var maximumMB: String
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            LabeledContent("Dışlanacak adlar") { TextField(".git, node_modules, .cache",text:$excluded).textFieldStyle(.roundedBorder).accessibilityLabel("Dışlanacak dosya veya klasör adları") }
            LabeledContent("Yalnız bu uzantılar") { TextField("pdf, txt — boşsa tümü",text:$extensions).textFieldStyle(.roundedBorder).accessibilityLabel("Dahil edilecek uzantılar") }
            LabeledContent("Yol şunu içersin") { TextField("Boşsa tüm yollar",text:$pathContains).textFieldStyle(.roundedBorder).accessibilityLabel("Yol filtresi") }
            HStack {
                Text("Dosya boyutu (MiB)").foregroundStyle(.secondary)
                TextField("En az",text:$minimumMB).textFieldStyle(.roundedBorder).accessibilityLabel("En küçük dosya boyutu MiB")
                Text("–")
                TextField("En çok",text:$maximumMB).textFieldStyle(.roundedBorder).accessibilityLabel("En büyük dosya boyutu MiB")
            }
            Text("Ad ve uzantıları virgülle ayır. Adlar tam eşleşir; klasör adı eşleşirse içindekiler de dışlanır. Kurallar birlikte uygulanır. Boş klasörler filtreli arşive eklenmez.").font(.caption).foregroundStyle(.secondary)
        }.padding(.top,10)
    }
}

struct FilterPreviewSheet: View {
    let inputs: [URL]
    let filter: ArchiveFilter
    let cleanMetadata: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var plan: CreationPlan?
    @State private var failure: String?
    @State private var control = OperationControl()
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Arşive eklenecekler").font(.title2.bold())
            if let plan {
                Text("\(plan.files.count) dosya · \(AppModel.size(plan.totalBytes)) · \(plan.excludedPaths.count) dosya dışlandı").foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:6) {
                        ForEach(Array(plan.files.prefix(300)),id:\.path) { file in Label(file.path,systemImage:"checkmark").textSelection(.enabled) }
                        if !plan.excludedPaths.isEmpty { Divider(); Text("Dışlananlar").font(.headline)
                            ForEach(Array(plan.excludedPaths.prefix(100)),id:\.self) { path in Label(path,systemImage:"minus.circle").foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                }.frame(height:320).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))
                if plan.files.isEmpty { Label("Filtreye uyan dosya yok.",systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                Text("Listeler en fazla 300 dahil edilen ve 100 dışlanan dosya gösterir. İşlem başladığında kaynaklar yeniden taranır.").font(.caption).foregroundStyle(.secondary)
            } else if let failure { Label(failure,systemImage:"exclamationmark.triangle").foregroundStyle(.red) }
            else { ProgressView("Kaynaklar taranıyor…").frame(maxWidth:.infinity,minHeight:250) }
            HStack { Spacer(); Button("Kapat") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width:650).tint(Theme.accent)
        .task {
            let active = control
            let result = await withTaskCancellationHandler {
                await Task.detached(priority:.userInitiated) { Result { try CreationPlan.build(inputs:inputs,filter:filter,cleanMetadata:cleanMetadata,control:active) } }.value
            } onCancel: { active.cancel() }
            guard !Task.isCancelled else { return }
            switch result { case .success(let value): plan = value; case .failure(let error): failure = error.localizedDescription }
        }.onDisappear { control.cancel() }
    }
}
