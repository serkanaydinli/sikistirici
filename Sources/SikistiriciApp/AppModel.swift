import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import ArchiveCore

enum AppResources {
    static func url(_ name: String, _ ext: String? = nil) -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return url }
        return Bundle.main.bundleURL.appendingPathComponent(name + (ext.map { "." + $0 } ?? ""))
    }
    static var icon: NSImage { NSImage(contentsOf: url("AppIcon", "png")) ?? NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil)! }
}

struct JobRow: Identifiable {
    enum State { case waiting, running, done, failed, cancelled }
    let id: UUID
    let title: String
    let subtitle: String
    var state: State = .waiting
    var fraction: Double?
    var detail = "Sırada"
    var output: URL?
    var startedAt: Date?
    var finishedAt: Date?
    var outcome: OperationOutcome?
}

enum JobRequest {
    case create([URL], URL, ArchiveFormat, Int, String?, Bool, Int64? = nil, ArchiveFilter = ArchiveFilter())
    case extract(URL, URL, [String]?, String?, CollisionPolicy, FilenameEncoding = .automatic)
    case verify(URL, String?, FilenameEncoding = .automatic)
    case edit(URL, ArchiveChanges, URL?, String?, FilenameEncoding = .automatic)
}

struct PasswordRequest: Identifiable { let id = UUID(); let url: URL }
struct SizeLimitRequest: Identifiable { let id = UUID(); let url: URL; let message: String }
private struct RecoveryAction {
    let id: UUID
    let retry: (String?) -> Void
    let cancel: () -> Void
}

@MainActor
final class AppModel: ObservableObject {
    @Published var inferredFilenameEncoding = false
    @Published var showingEncoding = false
    @Published var filenameEncoding: FilenameEncoding = .automatic
    @Published var profiles: [ArchiveProfile] = []
    @Published var editHistory = EditHistory()
    @Published var showingBatch = false
    @Published var batchInputs: [URL] = []
    @Published var batchMode: BatchMode = .compress
    @Published var showingEdits = false
    @Published var changes = ArchiveChanges()
    @Published var renamePath: String?
    @Published var renameValue = ""
    @Published var lastCompletion: UUID?
    @Published var archiveURL: URL?
    @Published var entries: [ArchiveEntry] = [] { didSet { analysis = ArchiveAnalysis(entries:entries) } }
    @Published var analysis = ArchiveAnalysis(entries:[])
    @Published var archiveReady = false
    @Published var showingAnalysis = false
    @Published var category: ArchiveCategory = .all { didSet { if category != oldValue { selection = [] } } }
    @Published var sort: ArchiveSort = .name
    @Published var directory = ""
    @Published var search = "" { didSet { if search != oldValue { selection = [] } } }
    @Published var selection = Set<String>()
    @Published var loading = false
    @Published var jobs: [JobRow] = []
    @Published var recent: [URL] = []
    @Published var showingCreate = false
    @Published var showingExtract = false
    @Published var showingPreview = false
    @Published var previewLoading = false
    @Published var previewURL: URL?
    @Published var errorMessage: String?
    @Published var passwordRequest: PasswordRequest?
    @Published var sizeLimitRequest: SizeLimitRequest?
    private var recoveryAction: RecoveryAction?
    @Published var collision: CollisionPolicy = .rename
    @Published var expansionLimitGB: Double = 20
    var draftInputs: [URL] = []
    var archivePassword: String?
    private let preferences: UserDefaults
    private var requests: [UUID: JobRequest] = [:]
    private var activeID: UUID?
    private var activeControl: OperationControl?
    private var browseControl: OperationControl?
    private var browseToken = UUID()
    private var previewControl: OperationControl?
    private var previewRoot: URL?
    private var previewToken = UUID()
    private var inFlightOperations = 0
    private var terminating = false
    private var commandObservers = Set<AnyCancellable>()

    var engine: ArchiveEngine {
        ArchiveEngine(executable: AppResources.url("7zz"), safety: SafetyPolicy(maximumExpandedBytes: Int64(expansionLimitGB * 1_073_741_824)))
    }
    var isWorking: Bool { jobs.contains { $0.state == .running } }
    var canEdit: Bool { archiveURL.map { ["zip","7z"].contains($0.pathExtension.lowercased()) } == true && archiveReady && !loading && !hasPendingJobs }
    var hasPendingJobs: Bool { jobs.contains { $0.state == .waiting || $0.state == .running } }
    var fileCount: Int { analysis.fileCount }
    var totalSize: Int64 { analysis.totalBytes }
    var selectedEntry: ArchiveEntry? { selection.count == 1 ? visibleEntries.first { selection.contains($0.id) } : nil }
    var selectedFiles: [ArchiveEntry] { ArchiveCatalog.selectedFiles(entries,paths:selection) }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var globalSearch: Bool { !search.isEmpty || category != .all }
    var visibleEntries: [ArchiveEntry] {
        ArchiveCatalog.visible(entries,directory:directory,query:search,category:category,sort:sort)
    }
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        // SwiftUI command enablement must follow the native field editor's undo stack too.
        let notifications: [Notification.Name] = [NSText.didBeginEditingNotification, NSText.didEndEditingNotification,
            NSText.didChangeNotification, Notification.Name.NSUndoManagerDidCloseUndoGroup,
            Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange]
        for name in notifications {
            NotificationCenter.default.publisher(for:name).receive(on:RunLoop.main).sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in:&commandObservers)
        }
        do { profiles = try ProfileStorage.load() } catch { errorMessage = "Kaydedilmiş profiller okunamadı: " + error.localizedDescription }
        recent = (preferences.stringArray(forKey: "recentArchives") ?? []).map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    func removeRecent(_ url: URL) {
        recent.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        preferences.set(recent.map(\.path),forKey:"recentArchives")
    }
    func clearRecent() {
        recent = []; preferences.removeObject(forKey:"recentArchives")
    }
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    func chooseArchive() {
        let panel = NSOpenPanel(); panel.title = "Arşiv aç"; panel.prompt = "Aç"
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { openArchive(url) }
    }
    func chooseInputs() {
        let panel = NSOpenPanel(); panel.title = "Sıkıştırılacak dosya ve klasörler"; panel.prompt = "Ekle"
        panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { draftInputs = panel.urls; showingCreate = true }
    }
    func newArchive() { draftInputs = []; showingCreate = true }
    func receive(_ urls: [URL]) {
        if urls.count == 1, let url = urls.first, url.scheme == "sikistirici" {
            do {
                let request = try FinderRequest(url: url)
                guard request.files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw ArchiveFailure.engine("Finder seçiminin bazı dosyaları artık yok.") }
                if request.action == .compress { guard confirmDraft() else { return }; draftInputs = request.files; showingCreate = true }
                else { presentBatch(request.files, mode: .extract) }
            } catch { errorMessage = error.localizedDescription }
            return
        }

        let archiveExtensions = Set(["zip","7z","rar","tar","gz","bz2","xz","tgz","tbz2","txz","zst","iso","cab","001"])
        if urls.count > 1, urls.allSatisfy({ archiveExtensions.contains($0.pathExtension.lowercased()) }) { presentBatch(urls, mode: .extract) }
        else if urls.count == 1, let url = urls.first, archiveExtensions.contains(url.pathExtension.lowercased()) { openArchive(url) }
        else { draftInputs = urls; showingCreate = true }
    }
    func openArchive(_ url: URL, password: String? = nil, encoding: FilenameEncoding = .automatic) {
        guard !terminating, confirmDraft() else { return }
        cancelRecovery()
        invalidatePreview()
        browseControl?.cancel(); let control = OperationControl(); browseControl = control
        let token = UUID(); browseToken = token
        resetChanges(); archiveReady = false; passwordRequest = nil; showingAnalysis = false; category = .all; filenameEncoding = encoding; inferredFilenameEncoding = false
        archiveURL = url; entries = []; directory = ""; search = ""; selection = []; archivePassword = nil; loading = true
        let engine = self.engine
        inFlightOperations += 1
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try engine.read(url, password: password, control: control, encoding:encoding)
                await self?.didOpen(result, url: url, password: password, token: token)
            } catch { await self?.failedOpen(error, url: url, token: token, password: password) }
            await self?.operationFinished()
        }
    }
    private func didOpen(_ result: ArchiveReadResult, url: URL, password: String?, token: UUID) {
        guard token == browseToken else { return }
        filenameEncoding = result.encoding; inferredFilenameEncoding = result.inferred
        entries = result.contents.entries; archiveReady = true; archivePassword = password; loading = false; browseControl = nil
        recent.removeAll { $0 == url }; recent.insert(url, at: 0); recent = Array(recent.prefix(8))
        preferences.set(recent.map(\.path), forKey: "recentArchives")
    }
    private func failedOpen(_ error: Error, url: URL, token: UUID, password: String?) {
        guard token == browseToken else { return }
        loading = false; browseControl = nil
        let encoding = filenameEncoding
        let previousPassword = password
        if !offerRecovery(error, url: url, retry: { [weak self] password in
            self?.openArchive(url, password: password ?? previousPassword, encoding: encoding)
        }) { if error as? ArchiveFailure != .cancelled { errorMessage = error.localizedDescription } }
    }
    /// Continuations capture their original archive, selection and output. A response is valid only
    /// for its request ID; closing/switching archives or cancelling discards it and any queued secret.
    @discardableResult
    private func offerRecovery(_ error: Error, url: URL, retry: @escaping (String?) -> Void,
                               cancel: @escaping () -> Void = {}) -> Bool {
        guard !terminating else { return false }
        let failure = error as? ArchiveFailure
        if failure == .passwordRequired || failure == .wrongPassword {
            guard recoveryAction == nil else { return false }
            let request = PasswordRequest(url: url)
            recoveryAction = RecoveryAction(id: request.id, retry: retry, cancel: cancel)
            passwordRequest = request
            return true
        }
        if case .limit(let message) = failure, expansionLimitGB < 100,
           (message.contains("açılmış boyutu") || message.contains("Açılan veriler boyut")) {
            guard recoveryAction == nil else { return false }
            let request = SizeLimitRequest(url: url, message: message)
            recoveryAction = RecoveryAction(id: request.id, retry: retry, cancel: cancel)
            sizeLimitRequest = request
            return true
        }
        return false
    }
    func submitPassword(_ password: String, request: PasswordRequest) {
        guard !password.isEmpty, passwordRequest?.id == request.id, let action = recoveryAction,
              action.id == request.id else { return }
        recoveryAction = nil; passwordRequest = nil
        if archiveURL?.standardizedFileURL == request.url.standardizedFileURL { archivePassword = password }
        action.retry(password)
    }
    func raiseLimitAndRetry(_ gigabytes: Double, requestID: UUID) {
        guard sizeLimitRequest?.id == requestID, let action = recoveryAction, action.id == requestID,
              [1.0, 5, 20, 100].contains(gigabytes), gigabytes > expansionLimitGB else { return }
        expansionLimitGB = gigabytes
        recoveryAction = nil; sizeLimitRequest = nil
        action.retry(nil)
    }
    func cancelRecovery() {
        let action = recoveryAction
        recoveryAction = nil; passwordRequest = nil; sizeLimitRequest = nil
        action?.cancel()
    }

    func closeArchive() {
        guard confirmDraft() else { return }
        cancelRecovery()
        invalidatePreview()
        browseToken = UUID(); browseControl?.cancel(); browseControl = nil; loading = false
        resetChanges(); archiveReady = false; passwordRequest = nil; showingAnalysis = false; category = .all; filenameEncoding = .automatic; inferredFilenameEncoding = false
        archiveURL = nil; archivePassword = nil; entries = []; search = ""; directory = ""; selection = []
    }
    func goTo(_ path: String) { directory = path; search = ""; category = .all; selection = [] }

    func enqueue(_ request: JobRequest, title: String, subtitle: String) {
        guard !terminating else { return }
        let id = UUID(); requests[id] = request
        jobs.insert(JobRow(id: id, title: title, subtitle: subtitle), at: 0)
        runNext()
    }
    private func runNext() {
        guard activeID == nil, let row = jobs.reversed().first(where: { $0.state == .waiting }), let request = requests[row.id] else { return }
        activeID = row.id; let control = OperationControl(); activeControl = control
        update(row.id) { $0.state = .running; $0.detail = "Hazırlanıyor…"; $0.startedAt = Date() }
        let engine = self.engine
        inFlightOperations += 1
        Task.detached(priority: .userInitiated) { [weak self] in
            let owner = self
            let progress: @Sendable (ProgressUpdate) -> Void = { update in
                Task { @MainActor in owner?.update(row.id) { $0.fraction = update.fraction; $0.detail = update.message } }
            }
            do {
                let result: OperationOutcome
                switch request {
                case .create(let inputs, let destination, let format, let level, let password, let clean, let volume, let filter):
                    result = try engine.create(inputs: inputs, destination: destination, format: format, level: level, password: password, cleanMetadata: clean, control: control, progress: progress, volumeBytes: volume, filter:filter)
                case .extract(let archive, let destination, let selected, let password, let collision, let encoding):
                    result = try engine.extract(archive, destination: destination, selected: selected, password: password, collision: collision, control: control, progress: progress, encoding:encoding)
                case .edit(let archive, let changes, let destination, let password, let encoding):
                    result = try engine.saveEdits(archive, changes: changes, destination: destination, password: password, control: control, progress: progress, encoding:encoding)
                case .verify(let archive, let password, let encoding):
                    try engine.verify(archive, password: password, control: control, progress: progress, encoding:encoding)
                    result = OperationOutcome(url: archive, fileCount: 0)
                }
                await self?.finished(row.id, result: result)
            } catch { await self?.failedJob(row.id, error: error) }
            await self?.operationFinished()
        }
    }
    private func update(_ id: UUID, _ body: (inout JobRow) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running || jobs[index].state == .waiting else { return }
        body(&jobs[index])
    }
    private func finished(_ id: UUID, result: OperationOutcome) {
        let verification: Bool
        if case .verify = requests[id] { verification = true } else { verification = false }
        let editedRequest: (URL,String?)?
        if case .edit(let source, _, _, let password, _) = requests[id] { editedRequest = (source,password) } else { editedRequest = nil }
        update(id) {
            $0.outcome = result; $0.finishedAt = Date()
            $0.state = .done; $0.fraction = 1; $0.output = result.url
            $0.detail = verification ? "Bütünlük testi başarılı" : "\(result.fileCount) dosya tamamlandı" + (result.skippedCount > 0 ? " · \(result.skippedCount) atlandı" : "")
        }
        requests.removeValue(forKey: id); activeID = nil; activeControl = nil; lastCompletion = UUID()
        if let (source,password) = editedRequest, archiveURL?.standardizedFileURL == source.standardizedFileURL {
            resetChanges(); showingEdits = false; openArchive(result.url,password:password)
        }
        runNext()
    }
    private func failedJob(_ id: UUID, error: Error) {
        activeControl = nil
        if let request = requests[id] {
            let url: URL?
            switch request {
            case .extract(let archive, _, _, _, _, _), .verify(let archive, _, _): url = archive
            default: url = nil
            }
            if let url, offerRecovery(error, url: url, retry: { [weak self] password in
                guard let self, self.activeID == id, self.requests[id] != nil else { return }
                switch request {
                case .extract(let archive, let destination, let selected, let previous, let collision, let encoding):
                    self.requests[id] = .extract(archive, destination, selected, password ?? previous, collision, encoding)
                case .verify(let archive, let previous, let encoding):
                    self.requests[id] = .verify(archive, password ?? previous, encoding)
                default: return
                }
                self.update(id) { $0.state = .waiting; $0.detail = "Yeniden deneniyor…" }
                self.activeID = nil; self.runNext()
            }, cancel: { [weak self] in self?.completeFailedJob(id, error: ArchiveFailure.cancelled) }) {
                update(id) { $0.detail = "Kullanıcı yanıtı bekleniyor…" }
                return
            }
        }
        completeFailedJob(id, error: error)
    }
    private func completeFailedJob(_ id: UUID, error: Error) {
        let cancelled = error as? ArchiveFailure == .cancelled
        update(id) { $0.finishedAt = Date(); $0.state = cancelled ? .cancelled : .failed; $0.detail = error.localizedDescription }
        requests.removeValue(forKey: id); activeID = nil; activeControl = nil; runNext()
    }
    func cancel(_ id: UUID) {
        if activeID == id { if recoveryAction != nil && activeControl == nil { cancelRecovery() } else { activeControl?.cancel() } }
        else {
            update(id) { $0.state = .cancelled; $0.detail = "İptal edildi" }
            requests.removeValue(forKey: id)
        }
    }
    func clearFinishedJobs() { jobs.removeAll { $0.state != .running && $0.state != .waiting } }
    func cancelAll() {
        for row in jobs where row.state == .waiting { cancel(row.id) }
        cancelRecovery()
        browseControl?.cancel(); previewControl?.cancel()
        activeControl?.cancel()
    }
    private func operationFinished() { inFlightOperations -= 1 }
    func cancelAndWaitForTermination() async {
        terminating = true
        cancelAll()
        while inFlightOperations > 0 { try? await Task.sleep(for: .milliseconds(50)) }
        invalidatePreview()
        archivePassword = nil
    }
    func extractToChosenFolder(selectedOnly: Bool, useSubfolder: Bool, password: String?) {
        guard let archive = archiveURL, archiveReady else { return }
        let panel = NSOpenPanel(); panel.title = "Çıkarma konumu"; panel.prompt = "Buraya çıkar"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let output = useSubfolder ? folder.appendingPathComponent(archive.deletingPathExtension().lastPathComponent) : folder
        let selected = selectedOnly ? Array(selection) : nil
        enqueue(.extract(archive, output, selected, password?.isEmpty == false ? password : archivePassword, collision, filenameEncoding), title: "Çıkar: \(archive.lastPathComponent)", subtitle: output.path)
        showingExtract = false
    }
    func testArchive() {
        guard let archive = archiveURL, archiveReady else { return }
        enqueue(.verify(archive, archivePassword, filenameEncoding), title: "Doğrula: \(archive.lastPathComponent)", subtitle: "Arşiv bütünlüğü")
    }
    func previewSelected() {
        guard !terminating, let archive = archiveURL, archiveReady, let entry = selectedEntry, !entry.isDirectory else { return }
        startPreview(archive: archive, path: entry.path, password: archivePassword, encoding: filenameEncoding)
    }
    private func startPreview(archive: URL, path: String, password: String?, encoding: FilenameEncoding) {
        previewControl?.cancel(); let control = OperationControl(); previewControl = control
        let token = UUID(); previewToken = token
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SikistiriciPreview-\(UUID())")
        let engine = self.engine
        previewLoading = true
        inFlightOperations += 1
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                _ = try engine.extract(archive, destination: root, selected: [path], password: password, control: control, encoding:encoding)
                await self?.didPreview(root: root, path: path, token: token)
            } catch { try? FileManager.default.removeItem(at: root); await self?.failedPreview(error, token: token, archive: archive, path: path, password: password, encoding: encoding) }
            await self?.operationFinished()
        }
    }
    private func didPreview(root: URL, path: String, token: UUID) {
        guard token == previewToken else { try? FileManager.default.removeItem(at: root); return }
        closePreview(); previewRoot = root; previewURL = root.appendingPathComponent(path); previewLoading = false; showingPreview = true
    }
    private func failedPreview(_ error: Error, token: UUID, archive: URL, path: String, password: String?, encoding: FilenameEncoding) {
        guard token == previewToken else { return }
        previewLoading = false; previewControl = nil
        if !offerRecovery(error, url: archive, retry: { [weak self] replacement in
            guard let self, self.previewToken == token else { return }
            self.startPreview(archive: archive, path: path, password: replacement ?? password, encoding: encoding)
        }), error as? ArchiveFailure != .cancelled { errorMessage = error.localizedDescription }
    }
    func closePreview() {
        if let root = previewRoot { try? FileManager.default.removeItem(at: root) }
        previewRoot = nil; previewURL = nil
    }
    private func invalidatePreview() {
        previewToken = UUID(); previewControl?.cancel(); previewControl = nil
        showingPreview = false; previewLoading = false; closePreview()
    }
}
