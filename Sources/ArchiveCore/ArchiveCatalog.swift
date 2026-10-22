import Foundation

public enum ArchiveCategory: String, CaseIterable, Identifiable, Sendable {
    case all, documents, images, media, archives, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "Tümü"
        case .documents: return "Belgeler"
        case .images: return "Görseller"
        case .media: return "Video / ses"
        case .archives: return "Arşivler"
        case .other: return "Diğer"
        }
    }
    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .media: return "play.rectangle"
        case .archives: return "archivebox"
        case .other: return "doc"
        }
    }
    public static func of(_ entry: ArchiveEntry) -> Self {
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "pdf","txt","md","rtf","doc","docx","xls","xlsx","csv","ppt","pptx","pages","numbers","key","odt": return .documents
        case "jpg","jpeg","png","gif","webp","heic","heif","tif","tiff","svg","bmp","avif","raw": return .images
        case "mp4","mov","mkv","avi","webm","m4v","mp3","wav","flac","aac","m4a","ogg","aiff": return .media
        case "zip","7z","rar","tar","gz","bz2","xz","tgz","zst": return .archives
        default: return .other
        }
    }
}

public enum ArchiveSort: String, CaseIterable, Identifiable, Sendable {
    case name, largest, smallest, type
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .name: return "Ada göre"
        case .largest: return "Büyükten küçüğe"
        case .smallest: return "Küçükten büyüğe"
        case .type: return "Türe göre"
        }
    }
}

public enum ArchiveCatalog {
    /// Search and category filters span the whole archive. Normal browsing stays in a folder.
    public static func visible(_ entries: [ArchiveEntry], directory: String, query: String, category: ArchiveCategory, sort: ArchiveSort) -> [ArchiveEntry] {
        let global = !query.isEmpty || category != .all
        var candidates: [ArchiveEntry]
        if global {
            candidates = entries.filter {
                (query.isEmpty || $0.path.localizedStandardContains(query)) &&
                (category == .all || (!$0.isDirectory && ArchiveCategory.of($0) == category))
            }
        } else {
            let prefix = directory.isEmpty ? "" : directory + "/"
            var children: [String:ArchiveEntry] = [:]
            for entry in entries where entry.path.hasPrefix(prefix) {
                let rest = String(entry.path.dropFirst(prefix.count))
                guard let first = rest.split(separator:"/").first else { continue }
                let path = prefix + first
                if rest.contains("/") {
                    if children[path] == nil { children[path] = ArchiveEntry(path:path,isDirectory:true) }
                } else { children[path] = entry }
            }
            candidates = Array(children.values)
        }
        return candidates.sorted { a,b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sort {
            case .largest: if a.size != b.size { return a.size > b.size }
            case .smallest: if a.size != b.size { return a.size < b.size }
            case .type:
                let ae = (a.name as NSString).pathExtension.lowercased()
                let be = (b.name as NSString).pathExtension.lowercased()
                if ae != be { return ae < be }
            case .name: break
            }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }

    /// Count each leaf once even when both its parent folder and the leaf are selected.
    public static func selectedFiles(_ entries: [ArchiveEntry], paths: Set<String>) -> [ArchiveEntry] {
        entries.filter { entry in
            guard !entry.isDirectory else { return false }
            if paths.contains(entry.path) { return true }
            var parent = (entry.path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if paths.contains(parent) { return true }
                parent = (parent as NSString).deletingLastPathComponent
            }
            return false
        }
    }

    /// JSON keeps Unicode, control characters and formula-like names as literal data.
    public static func inventory(_ entries: [ArchiveEntry], archiveName: String) throws -> Data {
        struct Item: Encodable {
            let path: String; let bytes: Int64; let directory: Bool; let encrypted: Bool
        }
        struct Manifest: Encodable {
            let schemaVersion: Int; let archive: String; let entries: [Item]
        }
        let manifest = Manifest(schemaVersion:1,archive:archiveName,entries:entries.sorted { $0.path < $1.path }.map {
            Item(path:$0.path,bytes:$0.size,directory:$0.isDirectory,encrypted:$0.encrypted)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }
}

public struct ArchiveAnalysis: Sendable {
    public struct Group: Identifiable, Sendable {
        public var id: ArchiveCategory { category }
        public let category: ArchiveCategory
        public let count: Int
        public let bytes: Int64
    }
    public let fileCount: Int
    public let totalBytes: Int64
    public let encryptedCount: Int
    public let largest: [ArchiveEntry]
    public let groups: [Group]
    public init(entries: [ArchiveEntry]) {
        let files = entries.filter { !$0.isDirectory }
        fileCount = files.count
        totalBytes = files.reduce(0) { $0 + $1.size }
        encryptedCount = files.filter(\.encrypted).count
        largest = Array(files.sorted { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }.prefix(10))
        let categories = Dictionary(grouping:files,by:ArchiveCategory.of)
        groups = categories.map { category,items in Group(category:category,count:items.count,bytes:items.reduce(0) { $0 + $1.size }) }
            .sorted { $0.bytes == $1.bytes ? $0.category.rawValue < $1.category.rawValue : $0.bytes > $1.bytes }
    }
}
