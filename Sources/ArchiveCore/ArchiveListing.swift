import Foundation

public enum ArchiveListing {
    public static func parse(_ text: String) throws -> ArchiveContents {
        var records: [[String: String]] = []
        var current: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .init(charactersIn: "\r"))
            if line.isEmpty {
                if !current.isEmpty { records.append(current); current = [:] }
                continue
            }
            if line == "Enter password:" || line.hasPrefix("Enter password (will not be echoed)") { continue }
            guard let range = line.range(of: " = ") else {
                throw ArchiveFailure.invalidArchive("Dosya listesinde desteklenmeyen satır veya dosya adı var.")
            }
            let key = String(line[..<range.lowerBound])
            guard current[key] == nil else { throw ArchiveFailure.invalidArchive("Belirsiz dosya listesi.") }
            current[key] = String(line[range.upperBound...])
        }
        if !current.isEmpty { records.append(current) }
        let entries = try records.map { record -> ArchiveEntry in
            guard let path = record["Path"], !path.isEmpty else { throw ArchiveFailure.invalidArchive("Dosya yolu eksik.") }
            let sizeText = record["Size"] ?? "0"
            guard let size = Int64(sizeText) else { throw ArchiveFailure.invalidArchive("Geçersiz dosya boyutu.") }
            let attributes = record["Attributes"] ?? ""
            let unixMode = attributes.split(separator: " ").first { $0.count >= 10 }
            let folder = record["Folder"] == "+" || attributes.first == "D" || unixMode?.first == "d"
            let link = !(record["Symbolic Link"] ?? "").isEmpty || !(record["Hard Link"] ?? "").isEmpty || !(record["Copy Link"] ?? "").isEmpty || unixMode?.first == "l"
            return ArchiveEntry(path: path, size: size, packedSize: Int64(record["Packed Size"] ?? "0") ?? 0,
                                isDirectory: folder, attributes: attributes, isLink: link, encrypted: record["Encrypted"] == "+")
        }
        return ArchiveContents(entries: entries)
    }
}

public struct SafetyPolicy: Sendable {
    public var maximumEntries: Int = 100_000
    public var maximumExpandedBytes: Int64 = 20 * 1024 * 1024 * 1024
    public init(maximumEntries: Int = 100_000, maximumExpandedBytes: Int64 = 20 * 1024 * 1024 * 1024) {
        self.maximumEntries = maximumEntries; self.maximumExpandedBytes = maximumExpandedBytes
    }
    public func validate(_ entries: [ArchiveEntry]) throws {
        guard entries.count <= maximumEntries else { throw ArchiveFailure.limit("Arşivde çok fazla dosya var. Üst sınır: \(maximumEntries).") }
        var seen: [String: Bool] = [:]
        var total: Int64 = 0
        for entry in entries {
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(":"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !entry.isLink, !entry.attributes.split(separator: " ").contains(where: { $0.count >= 10 && $0.first == "l" }) else {
                throw ArchiveFailure.unsafePath(entry.path)
            }
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen[key] == nil else { throw ArchiveFailure.unsafePath("Aynı dosya adı birden fazla kez geçiyor: \(path)") }
            seen[key] = entry.isDirectory
            guard entry.size >= 0, entry.size <= maximumExpandedBytes - total else { throw ArchiveFailure.limit("Arşivin açılmış boyutu izin verilen sınırı aşıyor.") }
            total += entry.size
        }
        for key in seen.keys {
            var parent = (key as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                if seen[parent] == false { throw ArchiveFailure.unsafePath("Dosya ve klasör yolları çakışıyor: \(parent)") }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
    }
}
