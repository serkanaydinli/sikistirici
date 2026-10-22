import Foundation

public struct ArchiveFilter: Codable, Equatable, Sendable {
    public var excludedNames: [String]
    public var includedExtensions: [String]
    public var pathContains: String
    public var minimumBytes: Int64?
    public var maximumBytes: Int64?
    public init(excludedNames: [String] = [], includedExtensions: [String] = [], pathContains: String = "", minimumBytes: Int64? = nil, maximumBytes: Int64? = nil) {
        self.excludedNames = excludedNames; self.includedExtensions = includedExtensions; self.pathContains = pathContains
        self.minimumBytes = minimumBytes; self.maximumBytes = maximumBytes
    }
    public var isActive: Bool { !excludedNames.isEmpty || !includedExtensions.isEmpty || !pathContains.isEmpty || minimumBytes != nil || maximumBytes != nil }
    public func validate() throws {
        guard excludedNames.count <= 100, includedExtensions.count <= 100, pathContains.count <= 255,
              (excludedNames + includedExtensions).allSatisfy({ !$0.isEmpty && $0.count <= 255 && !$0.contains("/") && !$0.contains("\\") && !$0.contains("*") && !$0.contains("?") && !$0.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) }),
              minimumBytes.map({ $0 >= 0 }) ?? true, maximumBytes.map({ $0 >= 0 }) ?? true,
              minimumBytes == nil || maximumBytes == nil || minimumBytes! <= maximumBytes! else {
            throw ArchiveFailure.engine("Filtreyi kontrol et: adlar tam eşleşir; /, *, ? kullanılamaz. Boyutlar sıfırdan küçük, alt sınır üst sınırdan büyük olamaz.")
        }
    }
    public func includes(path: String, size: Int64) -> Bool {
        let excluded = Set(excludedNames.map { $0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"tr_TR")) })
        if path.split(separator:"/").contains(where:{ excluded.contains(String($0).folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"tr_TR"))) }) { return false }
        if !includedExtensions.isEmpty {
            let ext = (path as NSString).pathExtension.lowercased()
            if !includedExtensions.contains(where:{ $0.trimmingCharacters(in:CharacterSet(charactersIn:".")).lowercased() == ext }) { return false }
        }
        if !pathContains.isEmpty && path.range(of:pathContains,options:[.caseInsensitive,.diacriticInsensitive]) == nil { return false }
        return (minimumBytes.map { size >= $0 } ?? true) && (maximumBytes.map { size <= $0 } ?? true)
    }
}

public struct ArchiveProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var format: ArchiveFormat
    public var level: Int
    public var cleanMetadata: Bool
    public var volumeBytes: Int64?
    public var destinationFolder: String?
    public var filter: ArchiveFilter
    public init(id: UUID = UUID(), name: String, format: ArchiveFormat = .zip, level: Int = 5, cleanMetadata: Bool = false,
                volumeBytes: Int64? = nil, destinationFolder: String? = nil, filter: ArchiveFilter = ArchiveFilter()) {
        self.id = id; self.name = name; self.format = format; self.level = level; self.cleanMetadata = cleanMetadata
        self.volumeBytes = volumeBytes; self.destinationFolder = destinationFolder; self.filter = filter
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count <= 80, (0...9).contains(level),
              volumeBytes.map({ $0 >= 1_048_576 && $0 <= 104_857_600_000 }) ?? true,
              destinationFolder.map({ $0.hasPrefix("/") && $0.count <= 4096 }) ?? true else { throw ArchiveFailure.engine("Profil adı veya ayarları geçersiz.") }
        try filter.validate()
    }
}

public enum ProfileStorage {
    private static let key = "archiveProfiles.v1"
    public static func load(from defaults: UserDefaults = .standard) throws -> [ArchiveProfile] {
        guard let data = defaults.data(forKey:key) else { return [] }
        guard data.count <= 1_048_576 else { throw ArchiveFailure.engine("Profil kaydı çok büyük.") }
        let profiles = try JSONDecoder().decode([ArchiveProfile].self,from:data)
        try validate(profiles); return profiles
    }
    public static func save(_ profiles: [ArchiveProfile], to defaults: UserDefaults = .standard) throws {
        try validate(profiles)
        let data = try JSONEncoder().encode(profiles)
        guard data.count <= 1_048_576 else { throw ArchiveFailure.engine("Profil kaydı çok büyük.") }
        defaults.set(data,forKey:key)
    }
    private static func validate(_ profiles: [ArchiveProfile]) throws {
        guard profiles.count <= 100, Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map { $0.name.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() }).count == profiles.count else { throw ArchiveFailure.engine("En fazla 100 benzersiz profil saklanabilir.") }
        for profile in profiles { try profile.validate() }
    }
}

public struct CreationPlan: Sendable {
    struct Directory: Sendable { let source: URL; let path: String }
    public struct File: Sendable {
        public let source: URL
        public let path: String
        public let size: Int64
    }
    public let files: [File]
    public let excludedPaths: [String]
    let directories: [Directory]
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public static func build(inputs: [URL], filter: ArchiveFilter, cleanMetadata: Bool, control: OperationControl = OperationControl()) throws -> CreationPlan {
        try filter.validate(); try control.check()
        var rule = filter
        if cleanMetadata { rule.excludedNames += [".DS_Store","__MACOSX"] }
        let fm = FileManager.default
        var files: [File] = []; var excluded: [String] = []; var entries: [ArchiveEntry] = []; var directories: [Directory] = []
        var rootNames = Set<String>()
        let keys: Set<URLResourceKey> = [.isDirectoryKey,.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey]
        for input in inputs {
            try control.check()
            let root = input.standardizedFileURL.resolvingSymlinksInPath()
            let name = input.lastPathComponent
            guard rootNames.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw ArchiveFailure.engine("Kaynak adları çakışıyor.") }
            func inspect(_ url: URL, path: String) throws {
                try control.check()
                let values = try url.resourceValues(forKeys:keys)
                let size = Int64(values.fileSize ?? 0)
                guard values.isDirectory == true || values.isRegularFile == true, values.isSymbolicLink != true else { throw ArchiveFailure.unsafePath(path) }
                entries.append(ArchiveEntry(path:path,size:0,isDirectory:values.isDirectory == true))
                guard entries.count <= 100_000 else { throw ArchiveFailure.limit("En fazla 100.000 kaynak girdisi taranabilir.") }
                if values.isDirectory == true { directories.append(Directory(source:url,path:path)) }
                if values.isDirectory != true {
                    if rule.includes(path:path,size:size) { files.append(File(source:url,path:path,size:size)) }
                    else { excluded.append(path) }
                }
            }
            try inspect(input,path:name)
            if try input.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true {
                var enumerationError: Error?
                guard let iterator = fm.enumerator(at:root,includingPropertiesForKeys:Array(keys),errorHandler:{ _,error in enumerationError = error; return false }) else { throw ArchiveFailure.engine("Kaynak klasör okunamadı.") }
                for case let file as URL in iterator {
                    let relative = file.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count).joined(separator:"/")
                    try inspect(file,path:name + "/" + relative)
                }
                if let enumerationError { throw enumerationError }
            }
        }
        try SafetyPolicy(maximumExpandedBytes:Int64.max).validate(entries)
        return CreationPlan(files:files,excludedPaths:excluded,directories:directories)
    }
}

extension ArchiveEngine {
    func createFiltered(inputs: [URL], destination: URL, format: ArchiveFormat, level: Int, password: String?, cleanMetadata: Bool,
                        control: OperationControl, progress: @escaping @Sendable (ProgressUpdate) -> Void, volumeBytes: Int64?, filter: ArchiveFilter) throws -> OperationOutcome {
        let started = Date(); try validatePassword(password); try FilePublisher.safeDestination(destination)
        for input in inputs where (try input.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
            guard !destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(input.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { throw ArchiveFailure.engine("Arşivi kaynak klasörün dışına kaydet.") }
        }
        progress(ProgressUpdate(message:"Filtreye uyan dosyalar hazırlanıyor…"))
        let plan = try CreationPlan.build(inputs:inputs,filter:filter,cleanMetadata:cleanMetadata,control:control)
        guard !plan.files.isEmpty else { throw ArchiveFailure.engine("Filtreye uyan dosya yok. Filtreyi değiştir veya dosya ekle.") }
        try DiskBudget.require(plan.totalBytes * 2,at:destination,capacityProvider:capacityProvider)
        let fm = FileManager.default
        let root = destination.deletingLastPathComponent().appendingPathComponent(".sikistirici-filter-\(UUID())")
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:root) }
        for file in plan.files {
            try control.check()
            let target = root.appendingPathComponent(file.path)
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            guard try file.source.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey]).isSymbolicLink != true else { throw ArchiveFailure.unsafePath(file.path) }
            try fm.copyItem(at:file.source,to:target)
        }
        _ = try FilePublisher.inspectTree(root,maximumBytes:safety.maximumExpandedBytes,control:control)
        for directory in plan.directories.sorted(by:{ $0.path.count > $1.path.count }) {
            let target = root.appendingPathComponent(directory.path)
            if FilePublisher.exists(target) {
                let attrs = try fm.attributesOfItem(atPath:directory.source.path)
                if let mode = attrs[.posixPermissions] as? NSNumber { try fm.setAttributes([.posixPermissions:mode.intValue & 0o777],ofItemAtPath:target.path) }
                if let date = attrs[.modificationDate] { try fm.setAttributes([.modificationDate:date],ofItemAtPath:target.path) }
            }
        }
        let staged = try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).sorted { $0.path < $1.path }
        let result = try create(inputs:staged,destination:destination,format:format,level:level,password:password,cleanMetadata:cleanMetadata,control:control,progress:progress,volumeBytes:volumeBytes)
        return OperationOutcome(url:result.url,fileCount:result.fileCount,skippedCount:plan.excludedPaths.count,bytes:result.bytes,inputBytes:result.inputBytes,elapsedSeconds:Date().timeIntervalSince(started),outputFiles:result.outputFiles)
    }
}
