import SwiftUI
import AppKit
import ArchiveCore
import QuickLookUI
import UniformTypeIdentifiers

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "Sistem"; case .light: return "Açık"; case .dark: return "Koyu" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum Theme {
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light })
    }
    static let accent = adaptive(light:NSColor(red:0.68,green:0.31,blue:0.065,alpha:1),dark:NSColor(red:1,green:0.65,blue:0.32,alpha:1))
    static let navy = Color(red:0.09,green:0.20,blue:0.29)
    static let canvas = adaptive(light:NSColor(red:0.975,green:0.962,blue:0.94,alpha:1),dark:NSColor(red:0.105,green:0.11,blue:0.12,alpha:1))
    static let panel = adaptive(light:.white,dark:NSColor(red:0.15,green:0.155,blue:0.165,alpha:1))
    static let sidebar = adaptive(light:NSColor(red:0.935,green:0.92,blue:0.895,alpha:1),dark:NSColor(red:0.125,green:0.13,blue:0.14,alpha:1))
    static let line = Color.primary.opacity(0.075)
}

struct MainWindow: View {
    @ObservedObject var model: AppModel
    @State private var dragTarget = false
    @AppStorage("appAppearance") private var appearance: AppAppearance = .system
    @AppStorage("showArchiveInspector") private var showInspector = true
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if model.archiveURL == nil { welcome.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    HStack(spacing:12) {
                        ArchiveBrowser(model:model).frame(maxWidth:.infinity,maxHeight:.infinity)
                            .background(Theme.panel,in:RoundedRectangle(cornerRadius:14))
                            .clipShape(RoundedRectangle(cornerRadius:14))
                            .overlay { RoundedRectangle(cornerRadius:14).strokeBorder(Theme.line,lineWidth:1).allowsHitTesting(false) }
                        if showInspector { ArchiveInspector(model:model).frame(width:216).background(Theme.panel,in:RoundedRectangle(cornerRadius:14)).clipShape(RoundedRectangle(cornerRadius:14)) }
                    }.padding(12)
                }
                Divider()
                JobQueueView(model: model).frame(height: model.jobs.isEmpty ? 58 : 172)
            }
            .background(Theme.canvas)
        }
        .frame(minWidth: 1000, minHeight: 660)
        .preferredColorScheme(appearance.colorScheme)
        .tint(Theme.accent)
        .overlay { if dragTarget { RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 3).padding(5).allowsHitTesting(false) } }
        .onDrop(of: [.fileURL], isTargeted: $dragTarget, perform: acceptDrop)
        .sheet(isPresented: $model.showingAnalysis) { ArchiveInsights(model:model) }
        .sheet(isPresented: $model.showingCreate) { CreateSheet(model: model) }
        .sheet(isPresented: $model.showingEncoding) { EncodingSheet(model:model) }
        .sheet(isPresented: $model.showingBatch) { BatchSheet(model:model) }
        .sheet(isPresented: $model.showingEdits) { EditorSheet(model:model) }
        .sheet(isPresented: Binding(get:{ model.renamePath != nil },set:{ if !$0 { model.renamePath = nil } })) { RenameSheet(model:model) }
        .sheet(isPresented: $model.showingExtract) { ExtractSheet(model: model) }
        .sheet(item: $model.passwordRequest) { request in PasswordSheet(model: model, request: request).interactiveDismissDisabled() }
        .sheet(item: $model.sizeLimitRequest) { request in SizeLimitSheet(model: model, request: request).interactiveDismissDisabled() }
        .sheet(isPresented: $model.showingPreview, onDismiss: model.closePreview) {
            VStack(spacing: 0) {
                HStack { Text(model.previewURL?.lastPathComponent ?? "Önizleme").font(.headline); Spacer(); Button("Kapat") { model.showingPreview = false }.keyboardShortcut(.cancelAction) }.padding()
                Divider()
                if let url = model.previewURL { QuickPreview(url: url).frame(minWidth: 680, minHeight: 480) }
            }
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MascotView(working:model.isWorking,completion:model.lastCompletion,size:64)
                VStack(alignment: .leading, spacing: 2) { Text("Sıkıştırıcı").font(.system(size: 19, weight: .bold, design: .rounded)); Text("Az yer. Çok iş.").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top,22).padding(.bottom,24)
            Text("ÇALIŞMA ALANI").font(.system(size:9,weight:.semibold)).tracking(1.3).foregroundStyle(.secondary).padding(.bottom,10)
            sideAction("Arşiv aç", icon: "folder.badge.plus", action: model.chooseArchive)
            sideAction("Yeni arşiv", icon: "plus.app", action: model.newArchive)
            sideAction("Toplu işlem",icon:"square.stack.3d.up") { model.presentBatch() }
            sideAction("Finder entegrasyonu",icon:"puzzlepiece.extension") { FinderIntegration.showSetup() }
            Divider().padding(.vertical,22)
            HStack {
                Text("Son açılanlar").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Geçmiş listesini temizle",action:model.clearRecent).disabled(model.recent.isEmpty)
                } label: { Image(systemName:"ellipsis.circle").foregroundStyle(.secondary) }.menuStyle(.borderlessButton).frame(width:20).help("Geçmişi yönet; dosyalar silinmez")
            }.padding(.bottom,12)
            if model.recent.isEmpty {
                Text("Açtığın arşivler\nburada görünür.").font(.caption).foregroundStyle(.tertiary).lineSpacing(4)
            }
            ScrollView { VStack(spacing:0) {
            ForEach(model.recent, id: \.path) { url in
                Button { model.openArchive(url) } label: {
                    HStack(spacing: 8) { Image(systemName: "doc.zipper").foregroundStyle(Theme.accent); Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1); Spacer(minLength: 0) }
                        .padding(.vertical,9).padding(.horizontal,8).background(model.archiveURL == url ? Theme.accent.opacity(0.13) : Color.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle())
                }.buttonStyle(.plain).help(url.path)
                    .contextMenu {
                        Button("Aç") { model.openArchive(url) }
                        Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Divider()
                        Button("Geçmişten kaldır") { model.removeRecent(url) }
                    }
            }
            }}.frame(maxHeight:.infinity)
            Picker("Görünüm",selection:$appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().help("Uygulamanın görünümü").padding(.bottom,16)
            HStack(spacing: 7) { Image(systemName: "lock.shield"); Text("Dosyaların Mac’inde kalır.") }.font(.system(size: 10)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("Geliştirici: Serkan Aydınlı")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Açık kaynak · MIT · 0.4.5")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }.padding(.top, 12)
        }.padding(.horizontal,18).padding(.bottom,20).frame(maxHeight: .infinity).background(Theme.sidebar)
    }
    private func sideAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:10) {
                Image(systemName:icon).font(.system(size:14,weight:.medium)).foregroundStyle(Theme.accent).frame(width:27,height:27).background(Theme.accent.opacity(0.09),in:RoundedRectangle(cornerRadius:7))
                Text(title).font(.system(size:12,weight:.medium)); Spacer(minLength:0)
            }.padding(.horizontal,7).padding(.vertical,7)
        }.buttonStyle(QuietButtonStyle())
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.archiveURL?.lastPathComponent ?? "Biraz yer açalım.").font(.system(size: 19, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(model.archiveURL == nil ? "Arşivlerin için tek bir çalışma alanı" : "\(model.fileCount) dosya · \(AppModel.size(model.totalSize)) açılmış boyut").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if model.archiveURL != nil {
                Button { model.showingAnalysis = true } label: { Label("Analiz",systemImage:"chart.bar.xaxis") }.disabled(!model.archiveReady)
                Button { model.testArchive() } label: { Image(systemName: "checkmark.shield") }.help("Arşiv bütünlüğünü doğrula").disabled(!model.archiveReady)
                Button { model.showingExtract = true } label: { Label("Çıkar", systemImage: "arrow.up.doc") }.buttonStyle(.borderedProminent).disabled(!model.archiveReady)
                if model.canEdit { Button(action:model.stageAddition) { Image(systemName:"plus") }.help("Arşive dosya ekle") }
                if !model.changes.isEmpty { Button("Değişiklikler") { model.showingEdits = true }.tint(.orange) }
                Button { showInspector.toggle() } label: { Image(systemName:"sidebar.right") }.help("Ayrıntılar panelini göster / gizle").accessibilityLabel("Ayrıntılar panelini göster veya gizle")
                Button(action: model.closeArchive) { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Arşivi kapat")
            } else {
                Button(action: model.newArchive) { Label("Yeni arşiv", systemImage: "plus") }.controlSize(.large)
            }
        }.padding(.horizontal,24).padding(.vertical,19).controlSize(.large)
    }
    private var welcome: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    HStack(spacing:30) {
                        VStack(alignment:.leading,spacing:17) {
                            Text("Dosyalarına biraz yer aç.").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.accent)
                            Text("Büyük dosyalar,\nküçük dertler.")
                                .font(.system(size:36,weight:.bold,design:.rounded)).tracking(-0.9).fixedSize(horizontal:false,vertical:true)
                            Text("Arşivini aç, içindekilere göz at.\nYa da dosyalarını tek bir pakette topla.")
                                .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal:false,vertical:true)
                            HStack(spacing:12) {
                                Button(action:model.chooseArchive) { Label("Arşiv aç",systemImage:"folder").padding(.horizontal,7) }.buttonStyle(.borderedProminent)
                                Button(action:model.chooseInputs) { Label("Dosya seç",systemImage:"plus").padding(.horizontal,7) }.buttonStyle(.bordered)
                            }.controlSize(.extraLarge).padding(.top,3)
                        }
                        Spacer(minLength:0)
                        MascotView(working:model.isWorking,completion:model.lastCompletion,size:230)
                            .background { Circle().fill(Theme.accent.opacity(0.055)).frame(width:270,height:270).accessibilityHidden(true) }
                    }.padding(.horizontal,8)
                    HStack(spacing:12) {
                        welcomeAction("Yeni paket",subtitle:"ZIP veya 7z oluştur",icon:"archivebox",action:model.newArchive)
                        welcomeAction("Toplu işlem",subtitle:"Birden çok arşivi birlikte işle",icon:"square.stack.3d.up") { model.presentBatch() }
                    }
                    HStack(spacing:12) {
                        Image(systemName:"arrow.down.doc").font(.system(size:22,weight:.light)).foregroundStyle(Theme.accent)
                        VStack(alignment:.leading,spacing:4) {
                            Text("Dosyalarını buraya sürükle").font(.system(size:12,weight:.medium))
                            Text("Tek arşiv açılır · Birden çok arşiv toplu işleme gider").font(.system(size:11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("ZIP / 7z / RAR").font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                    }.padding(17).frame(maxWidth:.infinity).overlay { RoundedRectangle(cornerRadius:12).strokeBorder(Theme.accent.opacity(0.25),style:StrokeStyle(lineWidth:1,dash:[5,4])).allowsHitTesting(false) }
                }.frame(maxWidth:730).padding(30).frame(maxWidth:.infinity).frame(minHeight:geometry.size.height)
            }
        }
    }
    private func welcomeAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:13) {
                Image(systemName:icon).font(.system(size:21,weight:.light)).foregroundStyle(Theme.accent).frame(width:42,height:42).background(Theme.accent.opacity(0.09),in:RoundedRectangle(cornerRadius:10))
                VStack(alignment:.leading,spacing:5) {
                    Text(title).font(.system(size:14,weight:.semibold))
                    Text(subtitle).font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:"arrow.up.right").font(.system(size:12)).foregroundStyle(.secondary)
            }.padding(17).frame(maxWidth:.infinity,alignment:.leading).background(Theme.panel,in:RoundedRectangle(cornerRadius:13))
                .overlay { RoundedRectangle(cornerRadius:13).strokeBorder(Theme.line,lineWidth:1) }.contentShape(RoundedRectangle(cornerRadius:13))
        }.buttonStyle(QuietButtonStyle()).help(subtitle)
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup(); let collector = DroppedURLs()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { collector.add(url) }
                else if let url = item as? URL { collector.add(url) }
            }
        }
        group.notify(queue: .main) { if !collector.urls.isEmpty { model.receive(collector.urls) } }
        return true
    }
}

private final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [URL] = []
    func add(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

struct QuickPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}
