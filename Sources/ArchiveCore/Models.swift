import Foundation

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let packedSize: Int64
    public let isDirectory: Bool
    public let attributes: String
    public let isLink: Bool
    public let encrypted: Bool
    public var name: String { (path as NSString).lastPathComponent }
    public init(path: String, size: Int64 = 0, packedSize: Int64 = 0, isDirectory: Bool = false, attributes: String = "", isLink: Bool = false, encrypted: Bool = false) {
        self.path = path; self.size = size; self.packedSize = packedSize
        self.isDirectory = isDirectory; self.attributes = attributes; self.isLink = isLink; self.encrypted = encrypted
    }
}

public struct ArchiveContents: Sendable {
    public let entries: [ArchiveEntry]
    public var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }
    public init(entries: [ArchiveEntry]) { self.entries = entries }
}

public enum ArchiveFailure: Error, LocalizedError, Equatable, Sendable {
    case invalidArchive(String), unsafePath(String), limit(String), engine(String), cancelled, passwordRequired, wrongPassword
    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let s): return "Arşiv okunamadı: \(s)"
        case .unsafePath(let s): return "Güvenli olmayan arşiv girdisi: \(s)"
        case .limit(let s): return s
        case .engine(let s): return s
        case .cancelled: return "İşlem iptal edildi."
        case .passwordRequired: return "Bu arşiv için parola gerekiyor."
        case .wrongPassword: return "Parola yanlış veya şifreli arşiv hasarlı."
        }
    }
}

public enum ArchiveFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case zip, sevenZip = "7z"
    public var id: String { rawValue }
    public var title: String { self == .zip ? "ZIP" : "7z" }
}

public enum CollisionPolicy: String, CaseIterable, Identifiable, Sendable {
    case rename, skip, replace
    public var id: String { rawValue }
    public var title: String {
        switch self { case .rename: return "Yeniden adlandır"; case .skip: return "Var olanı koru"; case .replace: return "Üzerine yaz" }
    }
}

public struct ProgressUpdate: Sendable {
    public let fraction: Double?
    public let message: String
    public init(fraction: Double? = nil, message: String) { self.fraction = fraction; self.message = message }
}

public struct OperationOutcome: Sendable {
    public let url: URL
    public let fileCount: Int
    public let skippedCount: Int
    public let bytes: Int64
    public let inputBytes: Int64
    public let elapsedSeconds: TimeInterval
    public let outputFiles: [URL]
    public init(url: URL, fileCount: Int, skippedCount: Int = 0, bytes: Int64 = 0, inputBytes: Int64 = 0, elapsedSeconds: TimeInterval = 0, outputFiles: [URL]? = nil) {
        self.url = url; self.fileCount = fileCount; self.skippedCount = skippedCount; self.bytes = bytes
        self.inputBytes = inputBytes; self.elapsedSeconds = elapsedSeconds; self.outputFiles = outputFiles ?? [url]
    }
}
