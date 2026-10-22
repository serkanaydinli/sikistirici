import Foundation
import Darwin

enum FilePublisher {
    static let fm = FileManager.default
    static func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
    static func safeDestination(_ destination: URL) throws {
        var current = destination.standardizedFileURL
        while current.path != "/" {
            if let attributes = try? fm.attributesOfItem(atPath: current.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                let trustedAlias = ["/var": "/private/var", "/tmp": "/private/tmp"]
                let linkTarget = try fm.destinationOfSymbolicLink(atPath: current.path)
                guard let expected = trustedAlias[current.path], linkTarget == expected || "/" + linkTarget == expected else {
                    throw ArchiveFailure.unsafePath("Hedef yol bir sembolik bağlantı içeriyor: \(current.lastPathComponent)")
                }
            }
            current.deleteLastPathComponent()
        }
    }
    static func unique(_ url: URL) -> URL {
        if !exists(url) { return url }
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let name = base + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            index += 1
        }
    }
    static func inspectTree(_ root: URL, maximumBytes: Int64, control: OperationControl) throws -> (Int, Int64) {
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: []) else { return (0, 0) }
        var count = 0; var bytes: Int64 = 0; var inspected = 0
        var entries: [ArchiveEntry] = []
        for case let url as URL in iterator {
            try control.check()
            inspected += 1
            if inspected > 100_000 { throw ArchiveFailure.limit("Açılan girdi sayısı sınırı aştı.") }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
            if values.isSymbolicLink == true { throw ArchiveFailure.unsafePath(url.lastPathComponent) }
            let relative = String(systemPath(url).dropFirst((systemPath(root) + "/").count))
            entries.append(ArchiveEntry(path: relative, size: values.isRegularFile == true ? Int64(values.fileSize ?? 0) : 0, isDirectory: values.isRegularFile != true))
            let attributes = try fm.attributesOfItem(atPath: url.path)
            if let links = attributes[.referenceCount] as? NSNumber, links.intValue > 1, values.isRegularFile == true { throw ArchiveFailure.unsafePath("Sabit bağlantı: \(url.lastPathComponent)") }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size <= maximumBytes - bytes else { throw ArchiveFailure.limit("Açılan veriler boyut sınırını aştı.") }
                bytes += size; count += 1
            }
            if count > 100_000 { throw ArchiveFailure.limit("Açılan dosya sayısı sınırı aştı.") }
        }
        try SafetyPolicy(maximumExpandedBytes: maximumBytes).validate(entries)
        return (count, bytes)
    }
    static func reconcile(_ staging: URL, expected: [ArchiveEntry], selected: [String]?, safety: SafetyPolicy) throws {
        guard let iterator = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]) else { throw ArchiveFailure.invalidArchive("Çıkarılan içerik okunamadı.") }
        var actual: [ArchiveEntry] = []
        let rootPath = systemPath(staging) + "/"
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey])
            let absolute = systemPath(url)
            guard absolute.hasPrefix(rootPath) else { throw ArchiveFailure.unsafePath(url.lastPathComponent) }
            let path = String(absolute.dropFirst(rootPath.count))
            actual.append(ArchiveEntry(path: path, size: values.isDirectory == true ? 0 : Int64(values.fileSize ?? 0), isDirectory: values.isDirectory == true, isLink: values.isSymbolicLink == true))
            if actual.count > safety.maximumEntries { throw ArchiveFailure.limit("Çıkarılan girdi sayısı sınırı aştı.") }
        }
        try safety.validate(actual)
        let expectedFiles = Set(expected.filter { entry in
            !entry.isDirectory && (selected == nil || selected!.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") })
        }.map(\.path))
        let actualFiles = Set(actual.filter { !$0.isDirectory }.map(\.path))
        guard expectedFiles == actualFiles else {
            throw ArchiveFailure.invalidArchive("Çıkarılan dosya adları listeyle eşleşmedi. Desteklenmeyen bir dosya adı olabilir; hiçbir dosya hedefe taşınmadı.")
        }
    }
    private static func systemPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix("/var/") || path.hasPrefix("/tmp/") { path = "/private" + path }
        return path
    }
    private static func comparisonPath(_ url: URL) -> String {
        systemPath(url).precomposedStringWithCanonicalMapping.lowercased()
    }
    // The callback is an internal fault-injection seam; production callers leave it empty.
    static func publish(_ staging: URL, to destination: URL, policy: CollisionPolicy, control: OperationControl, protectedSources: [URL], afterChange: () throws -> Void = {}) throws -> OperationOutcome {
        struct PlannedFile { let source: URL; let target: URL; let replace: Bool; let size: Int64 }
        struct PublishedFile { let target: URL; let backup: URL? }
        var directories: [(source: URL, target: URL, attributes: [FileAttributeKey: Any], modified: FileModificationTime)] = []
        var existingDirectories: [(URL, [FileAttributeKey: Any], FileModificationTime)] = []
        func metadata(_ url: URL) throws -> [FileAttributeKey: Any] {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            var result: [FileAttributeKey: Any] = [:]
            if let permissions = attributes[.posixPermissions] as? NSNumber { result[.posixPermissions] = permissions.intValue & 0o777 }
            return result
        }
        var planned: [PlannedFile] = []
        var reserved = Set<String>()
        var skipped = 0
        func occupied(_ url: URL) -> Bool { exists(url) || reserved.contains(comparisonPath(url)) }
        func availableName(_ url: URL) -> URL {
            if !occupied(url) { return url }
            let ext = url.pathExtension
            let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            var index = 2
            while true {
                let candidate = url.deletingLastPathComponent().appendingPathComponent(base + " (\(index))" + (ext.isEmpty ? "" : "." + ext))
                if !occupied(candidate) { return candidate }
                index += 1
            }
        }
        func plan(_ source: URL, _ proposed: URL) throws {
            try control.check()
            var target = proposed
            try safeDestination(target)
            if protectedSources.contains(where: { comparisonPath(target) == comparisonPath($0) }) {
                switch policy {
                case .skip: skipped += 1; return
                case .rename: target = availableName(target)
                case .replace: throw ArchiveFailure.engine("Çıkarma işlemi kaynak arşivin üzerine yazamaz.")
                }
            }
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw ArchiveFailure.unsafePath(source.lastPathComponent) }
            var present = occupied(target)
            if values.isDirectory == true {
                if present {
                    let type = try? fm.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType
                    if type != .typeDirectory {
                        if policy == .skip { skipped += 1; return }
                        guard policy == .rename else { throw ArchiveFailure.engine("Aynı adlı dosya ve klasör çakışıyor: \(target.lastPathComponent)") }
                        target = availableName(target); present = false
                    }
                }
                if !present { directories.append((source, target, try metadata(source), try FileModificationTime(url: source))); reserved.insert(comparisonPath(target)) }
                else { existingDirectories.append((target, try metadata(target), try FileModificationTime(url: target))) }
                for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try plan(child, target.appendingPathComponent(child.lastPathComponent))
                }
            } else {
                if present {
                    switch policy {
                    case .skip: skipped += 1; return
                    case .rename: target = availableName(target); present = false
                    case .replace:
                        guard try fm.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType == .typeRegular else { throw ArchiveFailure.engine("Hedef normal bir dosya değil: \(target.lastPathComponent)") }
                    }
                }
                reserved.insert(comparisonPath(target))
                planned.append(PlannedFile(source: source, target: target, replace: present, size: Int64(values.fileSize ?? 0)))
            }
        }
        try safeDestination(destination)
        if exists(destination) {
            guard try fm.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType == .typeDirectory else { throw ArchiveFailure.engine("Hedef bir klasör değil.") }
        }
        if exists(destination) { existingDirectories.append((destination, try metadata(destination), try FileModificationTime(url: destination))) }
        for child in try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try plan(child, destination.appendingPathComponent(child.lastPathComponent))
        }
        // Recovery data lives beside staging inside the writable destination.
        let recovery = destination.appendingPathComponent(".sikistirici-recovery-\(UUID())")
        var created: [URL] = []
        var published: [PublishedFile] = []
        var recoveryCreated = false
        var recoveryIndex: [String: String] = [:]
        do {
            var missing: [URL] = []
            var parent = destination
            while !exists(parent) { missing.append(parent); parent.deleteLastPathComponent() }
            for directory in missing.reversed() {
                try control.check(); try fm.createDirectory(at: directory, withIntermediateDirectories: false); created.append(directory)
            }
            for (_, target, _, _) in directories {
                try control.check(); try safeDestination(target)
                try fm.createDirectory(at: target, withIntermediateDirectories: false); created.append(target)
            }
            for item in planned {
                try control.check(); try safeDestination(item.target)
                var backup: URL?
                if item.replace {
                    if !recoveryCreated {
                        try fm.createDirectory(at: recovery, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); recoveryCreated = true
                    }
                    backup = recovery.appendingPathComponent(String(published.count))
                    recoveryIndex[item.target.path] = backup!.lastPathComponent
                    try JSONSerialization.data(withJSONObject: recoveryIndex, options: [.prettyPrinted, .sortedKeys]).write(to: recovery.appendingPathComponent("original-paths.json"), options: .atomic)
                    try fm.moveItem(at: item.target, to: backup!)
                } else if exists(item.target) { throw ArchiveFailure.engine("Hedef işlem sırasında değişti: \(item.target.lastPathComponent)") }
                published.append(PublishedFile(target: item.target, backup: backup))
                try fm.moveItem(at: item.source, to: item.target)
                try afterChange()
            }
            for (_, target, attributes, modified) in directories.reversed() {
                try control.check()
                try fm.setAttributes(attributes, ofItemAtPath: target.path)
                try modified.apply(to: target)
            }
            try control.check()
        } catch {
            var rollbackFailed = false
            // Do not consult cancellation during recovery. Undo our directory modes
            // first so restored read-only metadata cannot prevent removing new files.
            for directory in created {
                do { try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) } catch { rollbackFailed = true }
            }
            for item in published.reversed() {
                do {
                    if exists(item.target) { try fm.removeItem(at: item.target) }
                    if let backup = item.backup { try fm.moveItem(at: backup, to: item.target) }
                } catch { rollbackFailed = true }
            }
            if !rollbackFailed && recoveryCreated {
                do { try fm.removeItem(at: recovery); recoveryCreated = false } catch { rollbackFailed = true }
            }
            for directory in created.reversed() {
                do {
                    // Never recursively remove files introduced by another process.
                    guard rmdir(directory.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                } catch { rollbackFailed = true }
            }
            for (directory, attributes, modified) in existingDirectories.reversed() {
                do { try fm.setAttributes(attributes, ofItemAtPath: directory.path); try modified.apply(to: directory) } catch { rollbackFailed = true }
            }
            if rollbackFailed {
                let recoveryMessage = recoveryCreated ? "Kurtarma yedekleri korunuyor: \(recovery.path)." : "Hedefteki dosyaları kontrol edin; diğer işlemlerin eklediği dosyalar korundu."
                throw ArchiveFailure.engine("İşlem başarısız oldu ve bazı değişiklikler geri alınamadı. \(recoveryMessage) Asıl hata: \(error.localizedDescription)")
            }
            if recoveryCreated { try? fm.removeItem(at: recovery) }
            throw error
        }
        if recoveryCreated { try? fm.removeItem(at: recovery) }
        return OperationOutcome(url: destination, fileCount: planned.count, skippedCount: skipped, bytes: planned.reduce(0) { $0 + $1.size })
    }
}
