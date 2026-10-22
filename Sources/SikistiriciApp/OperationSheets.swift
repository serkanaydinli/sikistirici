import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiveCore

struct CreateSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: [URL]
    @State private var format: ArchiveFormat = .zip
    @State private var level = 5.0
    @State private var profile = "Dengeli"
    @State private var cleanMetadata = false
    @State private var encrypted = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var advanced = false
    @State private var split = false
    @State private var volumeMB = "100"
    @State private var excluded = ""
    @State private var includedExtensions = ""
    @State private var pathContains = ""
    @State private var minimumMB = ""
    @State private var maximumMB = ""
    @State private var showFilters = false
    @State private var showProfiles = false
    @State private var showFilterPreview = false
    @State private var profileName = ""
    @State private var destinationFolder: URL?
    @State private var localError: String?
    private var selectedProfile: ArchiveProfile? { model.profiles.first { "saved." + $0.id.uuidString == profile } }
    private var filterResult: Result<ArchiveFilter,Error> {
        Result {
            func bytes(_ value: String) throws -> Int64? {
                let text = value.trimmingCharacters(in:.whitespaces)
                if text.isEmpty { return nil }
                guard let n = Int64(text), n >= 0, n <= 100_000_000 else { throw ArchiveFailure.engine("Boyut sınırları 0–100.000.000 arasında tam MiB olmalı.") }
                return n * 1_048_576
            }
            func parts(_ value: String) -> [String] { value.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty } }
            let rule = ArchiveFilter(excludedNames:parts(excluded),includedExtensions:parts(includedExtensions),pathContains:pathContains,minimumBytes:try bytes(minimumMB),maximumBytes:try bytes(maximumMB))
            try rule.validate(); return rule
        }
    }
    private var filterError: String? { if case .failure(let error) = filterResult { return error.localizedDescription }; return nil }
    private var validVolume: Bool { !split || (Int64(volumeMB).map { $0 >= 1 && $0 <= 100_000 } ?? false) }
    init(model: AppModel) { self.model = model; _inputs = State(initialValue: model.draftInputs) }

    var body: some View {
        VStack(spacing:0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 13) {
                MascotView(working:model.isWorking,completion:model.lastCompletion,size:76)
                VStack(alignment: .leading, spacing: 5) { Text("Yeni arşiv").font(.system(size: 23,weight: .bold,design: .rounded)); Text("Dosyaları topla. Gerisini Sıkıştırıcı halletsin.").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Dosyalar ve klasörler").font(.headline); Spacer(); Button("Ekle…", action: addInputs) }
                if inputs.isEmpty {
                    Text("Sıkıştırmak istediğin dosya veya klasörleri ekle.").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius: 10))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(inputs, id: \.path) { url in
                                HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20,height: 20); Text(url.lastPathComponent).lineLimit(1); Spacer(); Button { inputs.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.borderless).help("Listeden kaldır") }.help(url.path)
                            }
                        }.padding(10)
                    }.frame(maxHeight: 120).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius: 10))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 15) {
                GridRow {
                    Text("Profil").foregroundStyle(.secondary)
                    Picker("Profil", selection: $profile) {
                        ForEach(["Dengeli","Windows’a gönder","Hızlı paketle","Daha küçük paketle"],id: \.self) { Text($0).tag($0) }
                        if !model.profiles.isEmpty { Divider() }
                        ForEach(model.profiles) { item in Text(item.name).tag("saved." + item.id.uuidString) }
                    }.labelsHidden()
                }
                GridRow {
                    Text("Biçim").foregroundStyle(.secondary)
                    Picker("Biçim", selection: $format) { ForEach(ArchiveFormat.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
            }
            DisclosureGroup("Profili kaydet ve yönet",isExpanded:$showProfiles) {
                VStack(alignment:.leading,spacing:12) {
                    LabeledContent("Profil adı") { TextField("Örn. Proje gönder",text:$profileName).textFieldStyle(.roundedBorder).accessibilityLabel("Profil adı") }
                    HStack {
                        Text(destinationFolder?.path ?? "Çıktı klasörü her seferinde seçilir").font(.caption).lineLimit(2)
                        Spacer(); Button("Çıktı klasörü…",action:chooseDefaultDestination)
                        if destinationFolder != nil { Button("Temizle") { destinationFolder = nil } }
                    }
                    HStack {
                        Button("Yeni profil kaydet") { saveProfile(updating:false) }.disabled(profileName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || filterError != nil || !validVolume)
                        if let selectedProfile {
                            Button("Profili güncelle") { saveProfile(updating:true) }.disabled(filterError != nil || !validVolume)
                            Button("Profili sil",role:.destructive) {
                                do { try model.deleteProfile(selectedProfile.id); profile = "Dengeli" } catch { localError = error.localizedDescription }
                            }
                        }
                    }
                    Text("Biçim, düzey, filtreler, parça boyutu ve çıktı klasörü Mac’inde saklanır. Parola ve parolayla koruma tercihi saklanmaz.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,10)
            }
            DisclosureGroup("Dosya filtreleri",isExpanded:$showFilters) {
                FilterEditor(excluded:$excluded,extensions:$includedExtensions,pathContains:$pathContains,minimumMB:$minimumMB,maximumMB:$maximumMB)
            }
            HStack {
                if case .success(let rule) = filterResult, rule.isActive { Label("Dosya filtresi etkin",systemImage:"line.3.horizontal.decrease.circle").font(.caption).foregroundStyle(Theme.accent) }
                Spacer(); Button("Eklenecekleri önizle") { showFilterPreview = true }.disabled(inputs.isEmpty || filterError != nil)
            }
            Toggle("Mac’e özgü gereksiz girdileri dışla", isOn: $cleanMetadata)
            Text("Açıksa .DS_Store ve __MACOSX eklenmez. Kaynakların değişmez.").font(.caption).foregroundStyle(.secondary).padding(.top,-12)
            Toggle("Parolayla koru (7z · AES-256)", isOn: $encrypted)
            if encrypted {
                HStack { SecureField("Parola", text: $password); SecureField("Parolayı doğrula", text: $confirmation) }
                Text("Parola kaydedilmez. Unutursan arşivi açamazsın.").font(.caption).foregroundStyle(.secondary).padding(.top,-12)
            }
            Toggle("Parçalara böl",isOn:$split)
            if split {
                HStack { Text("Parça boyutu"); TextField("MB",text:$volumeMB).frame(width:90); Text("MiB"); Spacer(); Menu("Hazır boyutlar") { ForEach([25,100,500,2000],id:\.self) { size in Button("\(size) MiB") { volumeMB = String(size) } } } }
                Text("Parçalar ayrı bir klasöre kaydedilir. Açarken bütün parçalar aynı klasörde olmalı.").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Sıkıştırma düzeyi", isExpanded: $advanced) {
                HStack { Text("Hızlı").font(.caption); Slider(value: $level,in:0...9,step:1); Text("Küçük").font(.caption); Text("\(Int(level))/9").monospacedDigit().frame(width: 33) }.padding(.top,10)
            }
            if let message = filterError ?? localError { Label(message,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
        }.padding(28)
        }
            Divider()
            HStack {
                Text("Fotoğraf ve videolarda kazanç sınırlı olabilir.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Konum seç ve sıkıştır", action: create).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(inputs.isEmpty || (encrypted && (password.isEmpty || password != confirmation)) || !validVolume || filterError != nil)
            }.padding(20)
        }.frame(width:680,height:min(800,(NSScreen.main?.visibleFrame.height ?? 900) - 100)).tint(Theme.accent)
        .sheet(isPresented:$showFilterPreview) {
            if case .success(let rule) = filterResult { FilterPreviewSheet(inputs:inputs,filter:rule,cleanMetadata:cleanMetadata) }
        }
        .onChange(of: profile) { _, value in applyProfile(value) }
        .onChange(of: encrypted) { _, value in if value { format = .sevenZip } }
        .onChange(of: format) { _, value in if value == .zip { encrypted = false } }
    }
    private func applyProfile(_ value: String) {
        localError = nil; encrypted = false; password = ""; confirmation = ""
        if let item = selectedProfile {
            format = item.format; level = Double(item.level); cleanMetadata = item.cleanMetadata
            split = item.volumeBytes != nil; volumeMB = String((item.volumeBytes ?? 104_857_600) / 1_048_576)
            excluded = item.filter.excludedNames.joined(separator:", "); includedExtensions = item.filter.includedExtensions.joined(separator:", ")
            pathContains = item.filter.pathContains
            minimumMB = item.filter.minimumBytes.map { String($0 / 1_048_576) } ?? ""
            maximumMB = item.filter.maximumBytes.map { String($0 / 1_048_576) } ?? ""
            destinationFolder = item.destinationFolder.map { URL(fileURLWithPath:$0) }; profileName = item.name
            showFilters = item.filter.isActive
        } else {
            format = value == "Daha küçük paketle" ? .sevenZip:.zip
            level = value == "Hızlı paketle" ? 1:(value == "Daha küçük paketle" ? 7:5)
            cleanMetadata = value == "Windows’a gönder"
            split = false; volumeMB = "100"; excluded = ""; includedExtensions = ""; pathContains = ""; minimumMB = ""; maximumMB = ""; destinationFolder = nil; profileName = ""
        }
    }
    private func chooseDefaultDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        if panel.runModal() == .OK { destinationFolder = panel.url }
    }
    private func saveProfile(updating: Bool) {
        do {
            let rule = try filterResult.get()
            let item = ArchiveProfile(id:updating ? (selectedProfile?.id ?? UUID()):UUID(),name:profileName.trimmingCharacters(in:.whitespacesAndNewlines),format:format,level:Int(level),cleanMetadata:cleanMetadata,volumeBytes:split ? (Int64(volumeMB) ?? 100) * 1_048_576:nil,destinationFolder:destinationFolder?.path,filter:rule)
            try model.saveProfile(item); profile = "saved." + item.id.uuidString; localError = nil
        } catch { localError = error.localizedDescription }
    }
    private func addInputs() {
        let panel = NSOpenPanel(); panel.title = "Dosya ve klasör ekle"; panel.prompt = "Ekle"; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { for url in panel.urls where !inputs.contains(url) { inputs.append(url) } }
    }
    private func create() {
        let panel = NSSavePanel(); panel.title = "Yeni arşivi kaydet"; panel.prompt = "Sıkıştır"
        panel.nameFieldStringValue = (inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent : "Arşiv") + "." + format.rawValue
        if let type = UTType(filenameExtension: format.rawValue) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        if let destinationFolder { panel.directoryURL = destinationFolder }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard case .success(let rule) = filterResult, validVolume else { return }
        model.enqueue(.create(inputs, destination, format, Int(level), encrypted ? password : nil, cleanMetadata, split ? (Int64(volumeMB) ?? 100) * 1_048_576 : nil, rule), title: "Sıkıştır: \(destination.lastPathComponent)", subtitle: "\(inputs.count) kaynak · \(format.title)")
        password = ""; confirmation = ""; dismiss()
    }
}

struct ExtractSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOnly: Bool
    @State private var subfolder = true
    @State private var password = ""
    init(model: AppModel) { self.model = model; _selectedOnly = State(initialValue: !model.selection.isEmpty) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Dosyaları çıkar", systemImage: "arrow.up.doc").font(.system(size: 23,weight: .bold,design: .rounded))
            Text(model.archiveURL?.lastPathComponent ?? "Arşiv").foregroundStyle(.secondary)
            Picker("Kapsam", selection: $selectedOnly) {
                Text("Tüm dosyalar").tag(false)
                Text("Yalnız seçilen \(model.selection.count) öğe").tag(true).disabled(model.selection.isEmpty)
            }.pickerStyle(.radioGroup)
            Toggle("Arşiv adıyla bir alt klasör oluştur", isOn: $subfolder)
            Picker("Aynı adlı dosya varsa", selection: $model.collision) { ForEach(CollisionPolicy.allCases) { Text($0.title).tag($0) } }
            if model.collision == .replace {
                Label("Hedefteki aynı adlı dosyalar değiştirilecek.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            SecureField("Parola (gerekiyorsa)", text: $password)
            HStack { Text("Açılmış boyut sınırı"); Spacer(); Picker("Açılmış boyut sınırı", selection: $model.expansionLimitGB) { ForEach([1.0,5,20,100],id: \.self) { Text("\(Int($0)) GB").tag($0) } }.labelsHidden().frame(width: 110) }.font(.system(size: 12))
            Text("Hata veya iptalde hedef değişiklikleri geri alınır. Geri alma tamamlanamazsa kurtarma yedeğinin konumu gösterilir.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            HStack { Spacer(); Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction); Button("Konum seç ve çıkar") { model.extractToChosenFolder(selectedOnly: selectedOnly,useSubfolder: subfolder,password: password); password = "" }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(selectedOnly && model.selection.isEmpty) }
        }.padding(28).frame(width: 510).tint(Theme.accent)
    }
}

struct PasswordSheet: View {
    @ObservedObject var model: AppModel
    let request: PasswordRequest
    @State private var password = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Bu arşiv kilitli", systemImage: "lock.fill").font(.system(size: 22,weight: .bold,design: .rounded))
            Text(request.url.lastPathComponent).font(.callout).foregroundStyle(.secondary)
            SecureField("Arşiv parolası", text: $password).textFieldStyle(.roundedBorder).focused($focused).onSubmit(open)
            Text("Parola yalnız bu oturumda kullanılır.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Vazgeç") { model.cancelRecovery() }.keyboardShortcut(.cancelAction); Button("Kilidi aç", action: open).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(password.isEmpty) }
        }.padding(28).frame(width: 410).tint(Theme.accent).onAppear { focused = true }
    }
    private func open() {
        guard !password.isEmpty else { return }
        let value = password; password = ""; model.submitPassword(value, request: request)
    }
}

struct SizeLimitSheet: View {
    @ObservedObject var model: AppModel
    let request: SizeLimitRequest
    @State private var limit = 100.0
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Arşiv boyut sınırını aşıyor", systemImage: "externaldrive.badge.exclamationmark").font(.title2.bold())
            Text(request.url.lastPathComponent).foregroundStyle(.secondary)
            Text(request.message)
            Text("Sınırı yalnız güvendiğiniz arşivler için yükseltin. Yol ve diğer güvenlik kontrolleri uygulanmaya devam eder.").font(.callout)
            Picker("Yeni açılmış boyut sınırı", selection: $limit) {
                ForEach([1.0, 5, 20, 100].filter { $0 > model.expansionLimitGB }, id: \.self) { Text("\(Int($0)) GB").tag($0) }
            }
            HStack {
                Spacer()
                Button("Vazgeç") { model.cancelRecovery() }.keyboardShortcut(.cancelAction)
                Button("Sınırı yükselt ve yeniden dene") { model.raiseLimitAndRetry(limit, requestID: request.id) }
                    .buttonStyle(.borderedProminent).disabled(limit <= model.expansionLimitGB)
            }
        }.padding(28).frame(width: 460).tint(Theme.accent)
    }
}
