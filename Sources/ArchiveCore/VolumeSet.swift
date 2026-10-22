import Foundation

public enum VolumeSet {
    public static func resolve(_ url: URL) throws -> URL { try members(url).first ?? url }
    public static func members(_ url: URL) throws -> [URL] {
        let name = url.lastPathComponent
        let patterns = [#"^(.*)\.(\d{3,})$"#, #"^(.*\.part)(\d+)(\.rar)$"#]
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            guard let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let prefixRange = Range(match.range(at: 1), in: name), let numberRange = Range(match.range(at: 2), in: name) else { continue }
            let prefix = String(name[prefixRange]); let digits = name[numberRange].count
            let suffix = match.numberOfRanges > 3 ? String(name[Range(match.range(at: 3), in: name)!]) : ""
            let folder = url.deletingLastPathComponent()
            let candidates = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).compactMap { item -> (Int, URL)? in
                let n = item.lastPathComponent
                guard let m = regex.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                      let pr = Range(m.range(at: 1), in: n), String(n[pr]).caseInsensitiveCompare(prefix) == .orderedSame,
                      let nr = Range(m.range(at: 2), in: n), let index = Int(n[nr]) else { return nil }
                return (index,folder.appendingPathComponent(item.lastPathComponent))
            }.sorted { $0.0 < $1.0 }
            guard !candidates.isEmpty else { throw ArchiveFailure.engine("Arşiv parçası bulunamadı: \(name)") }
            for (offset, candidate) in candidates.enumerated() {
                let required = offset + 1
                guard candidate.0 == required else {
                    throw ArchiveFailure.engine("Arşiv parçası eksik: \(prefix)" + (suffix.isEmpty ? "." : "") + String(format: "%0*d", digits, required) + suffix)
                }
            }
            return candidates.map(\.1)
        }
        return [url]
    }
}
