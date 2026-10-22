import Foundation

public struct ArchiveChanges: Sendable, Equatable {
    public var deletions: Set<String>
    public var renames: [String: String]
    public var additions: [URL]
    public var isEmpty: Bool { deletions.isEmpty && renames.isEmpty && additions.isEmpty }
    public init(deletions: Set<String> = [], renames: [String: String] = [:], additions: [URL] = []) {
        self.deletions = deletions; self.renames = renames; self.additions = additions
    }
    public func projectedEntries(_ entries: [ArchiveEntry]) throws -> [ArchiveEntry] {
        let policy = SafetyPolicy()
        try policy.validate(entries)
        let roots = Set(entries.map(\.path))
        for path in deletions.union(renames.keys) {
            guard roots.contains(path) || entries.contains(where: { $0.path.hasPrefix(path + "/") }) else { throw ArchiveFailure.engine("Değiştirilecek girdi bulunamadı: \(path)") }
            try policy.validate([ArchiveEntry(path: path)])
        }
        for (source,target) in renames {
            guard !deletions.contains(where: { source == $0 || source.hasPrefix($0 + "/") }) else { throw ArchiveFailure.engine("Silinecek bir girdi aynı zamanda yeniden adlandırılamaz.") }
            try policy.validate([ArchiveEntry(path: target)])
            guard !target.hasPrefix(source + "/"), !renames.keys.contains(where: { $0 != source && ($0.hasPrefix(source + "/") || source.hasPrefix($0 + "/")) }) else { throw ArchiveFailure.engine("İç içe klasörleri aynı adımda yeniden adlandıramazsın.") }
        }
        var result = entries.filter { entry in !deletions.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") } }.map { entry -> ArchiveEntry in
            let pair = renames.first { entry.path == $0.key || entry.path.hasPrefix($0.key + "/") }
            let path = pair.map { $0.value + entry.path.dropFirst($0.key.count) } ?? entry.path
            return ArchiveEntry(path: path, size: entry.size, packedSize: entry.packedSize, isDirectory: entry.isDirectory, attributes: entry.attributes, isLink: entry.isLink, encrypted: entry.encrypted)
        }
        let fm = FileManager.default
        for source in additions {
            let rootName = source.lastPathComponent
            let rootValues = try source.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
            result.append(ArchiveEntry(path: rootName, size: rootValues.isDirectory == true ? 0 : Int64(rootValues.fileSize ?? 0), isDirectory: rootValues.isDirectory == true, isLink: rootValues.isSymbolicLink == true))
            if rootValues.isDirectory == true {
                guard let iterator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]) else { throw ArchiveFailure.engine("Eklenecek klasör okunamadı.") }
                for case let file as URL in iterator {
                    let values = try file.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
                    let relative = file.pathComponents.dropFirst(source.pathComponents.count + (file.path.hasPrefix("/private/") && !source.path.hasPrefix("/private/") ? 1 : 0)).joined(separator: "/")
                    result.append(ArchiveEntry(path: rootName + "/" + relative, size: values.isDirectory == true ? 0 : Int64(values.fileSize ?? 0), isDirectory: values.isDirectory == true, isLink: values.isSymbolicLink == true))
                    if result.count > policy.maximumEntries { throw ArchiveFailure.limit("Çok fazla girdi var.") }
                }
            }
        }
        try policy.validate(result)
        guard !result.isEmpty else { throw ArchiveFailure.engine("Arşivde en az bir girdi kalmalı.") }
        return result
    }
}

extension ArchiveEngine {
    public func saveEdits(_ archive: URL, changes: ArchiveChanges, destination: URL? = nil, password: String? = nil,
                          control: OperationControl = OperationControl(), progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }, encoding: FilenameEncoding = .automatic) throws -> OperationOutcome {
        let started = Date(); try control.check()
        guard !changes.isEmpty else { throw ArchiveFailure.engine("Kaydedilecek değişiklik yok.") }
        guard let format = ArchiveFormat(rawValue: archive.pathExtension.lowercased()) else { throw ArchiveFailure.engine("Düzenleme yalnız tek parçalı ZIP ve 7z arşivlerinde desteklenir.") }
        if format == .zip, password?.isEmpty == false { throw ArchiveFailure.engine("Parolalı ZIP düzenleme desteklenmiyor. Dosyaları çıkarıp parolalı 7z oluşturabilirsin.") }
        let original = try ArchiveSnapshot(archive)
        let contents = try list(archive, password: password, control: control, encoding:encoding)
        let projected = try changes.projectedEntries(contents.entries)
        try safety.validate(projected)
        let output = destination ?? archive
        try FilePublisher.safeDestination(output)
        let fm = FileManager.default
        let expanded = max(contents.totalSize, projected.reduce(Int64(0)) { $0 + $1.size })
        try DiskBudget.require(expanded * 2, at: output, capacityProvider: capacityProvider)
        let workspace = output.deletingLastPathComponent().appendingPathComponent(".sikistirici-edit-\(UUID())")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let content = workspace.appendingPathComponent("content")
        _ = try extract(archive, destination: content, password: password, control: control, progress: progress, encoding:encoding)
        for path in changes.deletions.sorted(by: { $0.count > $1.count }) {
            try control.check()
            let target = content.appendingPathComponent(path)
            if FilePublisher.exists(target) { try fm.removeItem(at: target) }
        }
        var moved: [(URL,URL)] = []
        for (source,target) in changes.renames {
            try control.check()
            let current = content.appendingPathComponent(source)
            guard FilePublisher.exists(current) else { throw ArchiveFailure.engine("Yeniden adlandırılacak girdi silinmiş: \(source)") }
            let temporary = workspace.appendingPathComponent(UUID().uuidString)
            try fm.moveItem(at: current, to: temporary)
            moved.append((temporary,content.appendingPathComponent(target)))
        }
        for (temporary,target) in moved {
            guard !FilePublisher.exists(target) else { throw ArchiveFailure.engine("Yeni ad başka bir girdiyle çakışıyor: \(target.lastPathComponent)") }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: target)
        }
        for source in changes.additions {
            try control.check()
            let target = content.appendingPathComponent(source.lastPathComponent)
            guard !FilePublisher.exists(target) else { throw ArchiveFailure.engine("Eklenecek dosya adı çakışıyor: \(source.lastPathComponent)") }
            try fm.copyItem(at: source, to: target)
        }
        let inputs = try fm.contentsOfDirectory(at: content, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let rebuilt = try create(inputs: inputs, destination: workspace.appendingPathComponent("updated.\(format.rawValue)"), format: format, password: password, control: control, progress: progress)
        try verify(rebuilt.url, password: password, control: control, progress: progress)
        let actual = try list(rebuilt.url, password: password, control: control)
        guard Set(actual.entries.filter { !$0.isDirectory }.map(\.path)) == Set(projected.filter { !$0.isDirectory }.map(\.path)) else { throw ArchiveFailure.engine("Kaydedilen içerik beklenen değişikliklerle eşleşmedi. Asıl arşiv korundu.") }
        progress(ProgressUpdate(message: "Değişiklikler kaydediliyor…"))
        try control.check()
        guard try ArchiveSnapshot(archive) == original else { throw ArchiveFailure.engine("Arşiv başka bir işlem tarafından değiştirildi. Üzerine yazılmadı.") }
        let published: URL
        if destination == nil || output.standardizedFileURL == archive.standardizedFileURL {
            _ = try fm.replaceItemAt(archive, withItemAt: rebuilt.url)
            published = archive
        } else {
            published = FilePublisher.unique(output)
            try fm.moveItem(at: rebuilt.url, to: published)
        }
        return OperationOutcome(url: published, fileCount: actual.entries.filter { !$0.isDirectory }.count, bytes: rebuilt.bytes, inputBytes: rebuilt.inputBytes, elapsedSeconds: Date().timeIntervalSince(started))
    }
}
