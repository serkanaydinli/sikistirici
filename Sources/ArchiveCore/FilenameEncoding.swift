import Foundation
import CArchivePreview
import Darwin

public struct ArchiveReadResult: Sendable {
    public let contents: ArchiveContents
    public let encoding: FilenameEncoding
    public let inferred: Bool
}

extension ArchiveEngine {
    public func read(_ archive: URL, password: String? = nil, control: OperationControl = OperationControl(), encoding: FilenameEncoding = .automatic) throws -> ArchiveReadResult {
        let original = try listUnresolved(archive,password:password,control:control,encoding:encoding)
        guard encoding == .automatic, archive.pathExtension.lowercased() == "zip", Self.hasUndecodedNames(original) else {
            return ArchiveReadResult(contents:original,encoding:encoding,inferred:false)
        }
        // 7zz's POSIX UTF-8 decoder uses U+EF80...U+EFFF for undecoded filename bytes.
        // Probe UTF-8 first to preserve legitimately encoded Unicode, including private-use names.
        if let utf = try? listUnresolved(archive,password:password,control:control,encoding:.utf8) {
            if !Self.hasUndecodedNames(utf) || utf.entries.map(\.path) == original.entries.map(\.path) {
                return ArchiveReadResult(contents:utf,encoding:.utf8,inferred:true)
            }
        }
        var best: (ArchiveContents,FilenameEncoding,Int)?
        for candidate in [FilenameEncoding.windowsTurkish,.dosTurkish] {
            try control.check()
            guard let decoded = try? listUnresolved(archive,password:password,control:control,encoding:candidate), !Self.hasUndecodedNames(decoded) else { continue }
            let score = decoded.entries.reduce(0) { total,entry in
                total + entry.path.unicodeScalars.reduce(0) { score,scalar in
                    score + ("çğıöşüÇĞİÖŞÜ".unicodeScalars.contains(scalar) ? 3:0) - ((0x2500...0x259f).contains(scalar.value) ? 5:0)
                }
            }
            if score > 0 && score > (best?.2 ?? Int.min) { best = (decoded,candidate,score) }
        }
        try control.check()
        if let (contents,chosen,_) = best { return ArchiveReadResult(contents:contents,encoding:chosen,inferred:true) }
        return ArchiveReadResult(contents:original,encoding:.automatic,inferred:false)
    }
    private static func hasUndecodedNames(_ contents: ArchiveContents) -> Bool {
        contents.entries.contains { $0.path.unicodeScalars.contains { (0xef80...0xefff).contains($0.value) || $0.value == 0xfffd } }
    }
}

public enum FilenameEncoding: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, windowsTurkish, dosTurkish, utf8
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .windowsTurkish: return "Türkçe · Windows-1254"
        case .dosTurkish: return "Türkçe · DOS CP857"
        case .utf8: return "UTF-8"
        }
    }
    var charset: String {
        switch self { case .automatic, .utf8: return "UTF-8"; case .windowsTurkish: return "CP1254"; case .dosTurkish: return "CP857" }
    }
    func validateArchive(_ url: URL) throws {
        guard self == .automatic || url.pathExtension.lowercased() == "zip" else {
            throw ArchiveFailure.engine("Elle kodlama seçimi yalnız tek parçalı ZIP için kullanılabilir.")
        }
    }
}

// Keep the presence bit separate: an absent date must never become the Unix epoch.
struct FileModificationTime {
    let seconds: Int64
    let nanoseconds: Int64
    init?(isSet: Bool, seconds: Int64, nanoseconds: Int64) {
        guard isSet else { return nil }
        self.seconds = seconds; self.nanoseconds = nanoseconds
    }
    init(url: URL) throws {
        var info = stat()
        guard lstat(url.path,&info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
        self.seconds = Int64(info.st_mtimespec.tv_sec); self.nanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }
    func apply(to url: URL) throws {
        guard (0..<1_000_000_000).contains(nanoseconds) else { throw ArchiveFailure.invalidArchive("ZIP zaman damgası geçersiz.") }
        // Preserve access time while setting the exact archived nanosecond value.
        var existing = stat()
        guard lstat(url.path,&existing) == 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
        var times = [existing.st_atimespec,timespec(tv_sec:Int(seconds),tv_nsec:Int(nanoseconds))]
        guard utimensat(AT_FDCWD,url.path,&times,AT_SYMLINK_NOFOLLOW) == 0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
    }
}

private final class EncodedZIPContext {
    let control: OperationControl
    let safety: SafetyPolicy
    let root: URL?
    let selected: [String]?
    let deadline = Date().addingTimeInterval(1200)
    var entries: [ArchiveEntry] = []
    var error: Error?
    var handle: FileHandle?
    var currentURL: URL?
    var currentPermissions: Int = 0o600
    var currentModificationTime: FileModificationTime?
    var remaining: Int64 = 0
    var declared: Int64 = 0
    var written: Int64 = 0
    var directories: [(URL,Int,FileModificationTime?)] = []
    init(control: OperationControl, safety: SafetyPolicy, root: URL?, selected: [String]?) {
        self.control = control; self.safety = safety; self.root = root; self.selected = selected
    }
    func check() throws {
        try control.check()
        guard Date() < deadline else { throw ArchiveFailure.limit("Kodlamalı ZIP okuma süre sınırına ulaştı.") }
    }
    func finishFile() throws {
        if let handle {
            try handle.close(); self.handle = nil
            guard remaining == 0 else { throw ArchiveFailure.invalidArchive("Dosya boyutu ZIP başlığıyla eşleşmedi.") }
            if let currentURL {
                try currentModificationTime?.apply(to:currentURL)
                try FileManager.default.setAttributes([.posixPermissions:currentPermissions],ofItemAtPath:currentURL.path)
            }
        }
        currentURL = nil; currentModificationTime = nil
    }
    func header(_ path: String, size: Int64, directory: Bool, link: Bool, encrypted: Bool, permissions: Int, modificationTime: FileModificationTime?) throws -> Int32 {
        try check(); try finishFile()
        var name = path
        if directory, name.hasSuffix("/") { name.removeLast() }
        let entry = ArchiveEntry(path:name,size:size,isDirectory:directory,isLink:link,encrypted:encrypted)
        try safety.validate([entry])
        guard size <= safety.maximumExpandedBytes - declared else { throw ArchiveFailure.limit("Arşivin açılmış boyutu sınırı aşıyor.") }
        declared += size; entries.append(entry)
        guard let root else { return 2 }
        guard selected == nil || selected!.contains(where:{ name == $0 || name.hasPrefix($0 + "/") || directory && $0.hasPrefix(name + "/") }) else { return 2 }
        let url = root.appendingPathComponent(name)
        try FilePublisher.safeDestination(url)
        let fm = FileManager.default
        let mode = permissions == 0 ? (directory ? 0o700 : 0o600) : permissions
        if directory {
            try fm.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            directories.append((url,mode,modificationTime)); return 2
        }
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard !FilePublisher.exists(url), fm.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw ArchiveFailure.unsafePath("ZIP girdileri çakışıyor: \(name)") }
        handle = try FileHandle(forWritingTo:url); currentURL = url; currentPermissions = mode; currentModificationTime = modificationTime; remaining = size
        return 1
    }
    func data(_ bytes: UnsafeRawPointer, count: Int) throws {
        try check()
        guard let handle, Int64(count) <= remaining, Int64(count) <= safety.maximumExpandedBytes - written else { throw ArchiveFailure.limit("ZIP verisi bildirilen boyutu veya güvenlik sınırını aşıyor.") }
        try handle.write(contentsOf:Data(bytes:bytes,count:count)); remaining -= Int64(count); written += Int64(count)
    }
    deinit { try? handle?.close() }
}

enum EncodedZIPReader {
    static func read(_ url: URL, encoding: FilenameEncoding, password: String?, safety: SafetyPolicy, control: OperationControl,
                     root: URL? = nil, selected: [String]? = nil) throws -> ArchiveContents {
        try encoding.validateArchive(url)
        let context = EncodedZIPContext(control:control,safety:safety,root:root,selected:selected)
        var message = [CChar](repeating:0,count:1024)
        let status = sa_zip_read(url.path,encoding.charset,password,safety.maximumEntries,{ path,size,directory,link,encrypted,permissions,hasTime,seconds,nanoseconds,opaque in
            guard let path, let opaque else { return 0 }
            let ctx = Unmanaged<EncodedZIPContext>.fromOpaque(opaque).takeUnretainedValue()
            do { return try ctx.header(String(cString:path),size:size,directory:directory != 0,link:link != 0,encrypted:encrypted != 0,permissions:Int(permissions),modificationTime:FileModificationTime(isSet:hasTime != 0,seconds:seconds,nanoseconds:nanoseconds)) }
            catch { ctx.error = error; return 0 }
        },{ bytes,count,opaque in
            guard let bytes, let opaque else { return 0 }
            let ctx = Unmanaged<EncodedZIPContext>.fromOpaque(opaque).takeUnretainedValue()
            do { try ctx.data(bytes,count:count); return 1 } catch { ctx.error = error; return 0 }
        },Unmanaged.passUnretained(context).toOpaque(),&message,message.count)
        if let error = context.error { throw error }
        guard status == 0 else {
            if status == -3 { throw ArchiveFailure.limit("Arşivde çok fazla girdi var.") }
            let detail = String(cString:message)
            if ["passphrase","password","encrypt"].contains(where:{ detail.localizedCaseInsensitiveContains($0) }) {
                throw password?.isEmpty == false ? ArchiveFailure.wrongPassword : ArchiveFailure.passwordRequired
            }
            throw ArchiveFailure.invalidArchive("Seçilen kodlamayla ZIP okunamadı: " + String(detail.prefix(200)))
        }
        try context.finishFile()
        try safety.validate(context.entries)
        for (url,mode,modificationTime) in context.directories.sorted(by:{ $0.0.path.count > $1.0.path.count }) {
            try modificationTime?.apply(to:url)
            try FileManager.default.setAttributes([.posixPermissions:mode],ofItemAtPath:url.path)
        }
        return ArchiveContents(entries:context.entries)
    }
}
