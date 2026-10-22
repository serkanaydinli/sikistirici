import Foundation

public struct ArchiveEngine: Sendable {
    public let executable: URL
    public let safety: SafetyPolicy
    let capacityProvider: @Sendable (URL) throws -> Int64
    public init(executable: URL, safety: SafetyPolicy = SafetyPolicy(), capacityProvider: @escaping @Sendable (URL) throws -> Int64 = { try DiskBudget.available(at: $0) }) { self.executable = executable; self.safety = safety; self.capacityProvider = capacityProvider }
    public func list(_ archive: URL, password: String? = nil, control: OperationControl = OperationControl(), encoding: FilenameEncoding = .automatic) throws -> ArchiveContents {
        try read(archive,password:password,control:control,encoding:encoding).contents
    }
    func listUnresolved(_ archive: URL, password: String? = nil, control: OperationControl = OperationControl(), encoding: FilenameEncoding = .automatic) throws -> ArchiveContents {
        try control.check()
        try validatePassword(password)
        let archive = try VolumeSet.resolve(archive)
        try encoding.validateArchive(archive)
        if encoding != .automatic { return try EncodedZIPReader.read(archive, encoding:encoding, password:password, safety:safety, control:control) }
        let output = try EngineProcess(executable: executable).run(["l", "-slt", "-ba", "-sccUTF-8", "--", archive.path], password: password, control: control)
        let contents = try ArchiveListing.parse(output)
        try safety.validate(contents.entries)
        return contents
    }
    public func create(inputs: [URL], destination: URL, format: ArchiveFormat = .zip, level: Int = 5, password: String? = nil, cleanMetadata: Bool = false,
                       control: OperationControl = OperationControl(), progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }, volumeBytes: Int64? = nil, filter: ArchiveFilter = ArchiveFilter()) throws -> OperationOutcome {
        let started = Date()
        try filter.validate()
        if filter.isActive { return try createFiltered(inputs:inputs,destination:destination,format:format,level:level,password:password,cleanMetadata:cleanMetadata,control:control,progress:progress,volumeBytes:volumeBytes,filter:filter) }
        if let volumeBytes, volumeBytes < 1024 { throw ArchiveFailure.engine("Parça boyutu en az 1 KiB olmalı.") }
        try control.check(); try validatePassword(password)
        guard !inputs.isEmpty else { throw ArchiveFailure.engine("Önce dosya veya klasör seçin.") }
        if format == .zip && password?.isEmpty == false { throw ArchiveFailure.engine("Parolalı oluşturma için 7z biçimini seçin.") }
        try FilePublisher.safeDestination(destination)
        var names = Set<String>(); var files = 0; var inputBytes: Int64 = 0
        let fm = FileManager.default
        for input in inputs {
            let name = input.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(name).inserted, !input.lastPathComponent.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ArchiveFailure.engine("Kaynakların adları çakışıyor veya desteklenmeyen karakter içeriyor.") }
            try safety.validate([ArchiveEntry(path: input.lastPathComponent, size: 0, isDirectory: true)])
            let values = try input.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw ArchiveFailure.unsafePath(input.lastPathComponent) }
            if values.isDirectory == true {
                let sourcePath = input.standardizedFileURL.resolvingSymlinksInPath().path + "/"
                guard !destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(sourcePath) else { throw ArchiveFailure.engine("Arşivi kaynak klasörün dışına kaydedin.") }
                let tree = try FilePublisher.inspectTree(input, maximumBytes: Int64.max, control: control)
                files += tree.0; inputBytes += tree.1
            } else { files += 1; inputBytes += Int64(try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        }
        try DiskBudget.require(inputBytes, at: destination, capacityProvider: capacityProvider)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".sikistirici-create-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent(destination.lastPathComponent)

        var arguments = ["a", "-spd", "-t\(format.rawValue)", "-mx=\(min(9,max(0,level)))", "-mmt=2", "-bsp1", "-sccUTF-8"]
        if let volumeBytes { arguments.append("-v\(volumeBytes)b") }
        if password?.isEmpty == false { arguments += ["-p", "-mhe=on"] }
        if cleanMetadata { arguments += ["-xr!.DS_Store", "-xr!__MACOSX"] }
        let directory = inputs[0].deletingLastPathComponent()
        arguments += ["--", temporary.path] + inputs.map { $0.deletingLastPathComponent() == directory ? $0.lastPathComponent : $0.path }
        progress(ProgressUpdate(message: "Arşiv oluşturuluyor…"))
        _ = try EngineProcess(executable: executable).run(arguments, directory: directory, password: password, creatingPassword: true, control: control, progress: progress)
        try control.check()
        if volumeBytes != nil {
            let parts = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.fileSizeKey]).sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let first = parts.first else { throw ArchiveFailure.engine("Arşiv parçaları oluşturulamadı.") }
            _ = try VolumeSet.members(first)
            try verify(first, password: password, control: control, progress: progress)
            let size = try parts.reduce(Int64(0)) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
            let output = FilePublisher.unique(destination.appendingPathExtension("parçalar"))
            try fm.moveItem(at: staging, to: output)
            return OperationOutcome(url: output, fileCount: files, bytes: size, inputBytes: inputBytes, elapsedSeconds: Date().timeIntervalSince(started), outputFiles: parts.map { output.appendingPathComponent($0.lastPathComponent) })
        }
        try verify(temporary, password: password, control: control, progress: progress)
        try control.check()
        let output = FilePublisher.unique(destination)
        try fm.moveItem(at: temporary, to: output)
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return OperationOutcome(url: output, fileCount: files, bytes: Int64(size), inputBytes: inputBytes, elapsedSeconds: Date().timeIntervalSince(started))
    }
    public func extract(_ archive: URL, destination: URL, selected: [String]? = nil, password: String? = nil, collision: CollisionPolicy = .rename,
                        control: OperationControl = OperationControl(), progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }, encoding: FilenameEncoding = .automatic) throws -> OperationOutcome {
        try control.check()
        progress(ProgressUpdate(message: "Arşiv kontrol ediliyor…"))
        let started = Date()
        let archive = try VolumeSet.resolve(archive)
        let identity = try ArchiveSnapshot(archive)
        let resolved = try read(archive,password:password,control:control,encoding:encoding)
        let contents = resolved.contents
        let effectiveEncoding = resolved.encoding
        guard try ArchiveSnapshot(archive) == identity else { throw ArchiveFailure.engine("Arşiv işlem sırasında değişti. Yeniden açıp deneyin.") }
        try FilePublisher.safeDestination(destination)
        let selectedEntries = contents.entries.filter { entry in
            selected == nil || selected!.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") }
        }
        if selected != nil && selectedEntries.isEmpty { throw ArchiveFailure.engine("Çıkarılacak dosya seçilmedi.") }
        // Listing safety validation covers the entire archive. Space is needed for the
        // selected leaves only; filtering entries also deduplicates overlapping selections.
        let selectedBytes = selectedEntries.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.size }
        try DiskBudget.require(selectedBytes, at: destination, capacityProvider: capacityProvider)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let staging = destination.appendingPathComponent(".sikistirici-stage-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at: staging) }
        var arguments = ["x", "-y", "-aoa", "-spd", "-bsp1", "-sccUTF-8", "-scsUTF-8", "-o\(staging.path)"]
        let listingFile = fm.temporaryDirectory.appendingPathComponent("sikistirici-selection-\(UUID()).txt")
        defer { try? fm.removeItem(at: listingFile) }
        if let selected {
            let paths = contents.entries.filter { entry in selected.contains { entry.path == $0 || entry.path.hasPrefix($0 + "/") } }.map(\.path)
            guard !paths.isEmpty else { throw ArchiveFailure.engine("Çıkarılacak dosya seçilmedi.") }
            try Data(paths.joined(separator: "\n").utf8).write(to: listingFile, options: .atomic)
            arguments.append("-i@\(listingFile.path)")
        }
        arguments += ["--", archive.path]
        progress(ProgressUpdate(message: "Dosyalar çıkarılıyor…"))
        if effectiveEncoding == .automatic {
            _ = try EngineProcess(executable: executable).run(arguments, password: password, control: control, progress: progress) {
                _ = try FilePublisher.inspectTree(staging, maximumBytes: safety.maximumExpandedBytes, control: control)
            }
        } else {
            _ = try EncodedZIPReader.read(archive,encoding:effectiveEncoding,password:password,safety:safety,control:control,root:staging,selected:selected)
        }
        _ = try FilePublisher.inspectTree(staging, maximumBytes: safety.maximumExpandedBytes, control: control)
        guard try ArchiveSnapshot(archive) == identity else { throw ArchiveFailure.engine("Arşiv işlem sırasında değişti. Hiçbir dosya hedefe taşınmadı.") }
        try FilePublisher.reconcile(staging, expected: contents.entries, selected: selected, safety: safety)
        try control.check()
        progress(ProgressUpdate(message: "Dosyalar hedefe yerleştiriliyor…"))
        let result = try FilePublisher.publish(staging, to: destination, policy: collision, control: control, protectedSources: identity.urls)
        return OperationOutcome(url: result.url, fileCount: result.fileCount, skippedCount: result.skippedCount, bytes: result.bytes, inputBytes: contents.totalSize, elapsedSeconds: Date().timeIntervalSince(started))
    }
    public func verify(_ archive: URL, password: String? = nil, control: OperationControl = OperationControl(), progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }, encoding: FilenameEncoding = .automatic) throws {
        let archive = try VolumeSet.resolve(archive)
        _ = try list(archive, password: password, control: control, encoding:encoding)
        _ = try EngineProcess(executable: executable).run(["t", "-bsp1", "-sccUTF-8", "--", archive.path], password: password, control: control, progress: progress)
    }
    func validatePassword(_ password: String?) throws {
        if let password, password.contains("\n") || password.contains("\r") || password.contains("\0") {
            throw ArchiveFailure.engine("Parola satır sonu veya sıfır karakteri içeremez.")
        }
    }
}

struct ArchiveIdentity: Equatable {
    let size: UInt64
    let inode: UInt64
    let device: UInt64
    let modified: Date
    init(_ url: URL) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              let size = values[.size] as? NSNumber, let inode = values[.systemFileNumber] as? NSNumber,
              let device = values[.systemNumber] as? NSNumber, let modified = values[.modificationDate] as? Date else {
            throw ArchiveFailure.invalidArchive("Arşiv normal bir dosya değil.")
        }
        self.size = size.uint64Value; self.inode = inode.uint64Value; self.device = device.uint64Value; self.modified = modified
    }
}

struct ArchiveSnapshot: Equatable {
    let urls: [URL]
    let identities: [ArchiveIdentity]
    init(_ url: URL) throws {
        urls = try VolumeSet.members(url)
        identities = try urls.map(ArchiveIdentity.init)
    }
}
