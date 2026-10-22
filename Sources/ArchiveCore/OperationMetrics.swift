import Foundation

public enum OperationMetrics {
    public static func remainingSeconds(fraction: Double?, elapsed: TimeInterval) -> TimeInterval? {
        guard let fraction, fraction.isFinite, fraction >= 0.02, fraction < 1, elapsed >= 1 else { return nil }
        return elapsed * (1 - fraction) / fraction
    }
    public static func savings(inputBytes: Int64, outputBytes: Int64) -> Double? {
        guard inputBytes > 0 else { return nil }
        return 1 - Double(outputBytes) / Double(inputBytes)
    }
}

public enum DiskBudget {
    public static func available(at url: URL) throws -> Int64 {
        var current = url
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" { current.deleteLastPathComponent() }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: current.path)
        guard let bytes = attributes[.systemFreeSize] as? NSNumber else { throw ArchiveFailure.engine("Boş disk alanı okunamadı.") }
        return bytes.int64Value
    }
    public static func require(_ bytes: Int64, at url: URL, capacityProvider: @Sendable (URL) throws -> Int64 = { try DiskBudget.available(at: $0) }) throws {
        let available = try capacityProvider(url)
        let reserve: Int64 = 8 * 1024 * 1024
        guard bytes >= 0, available > reserve, bytes <= available - reserve else {
            throw ArchiveFailure.limit("Diskte yeterli boş alan yok. İşlem için yaklaşık \(ByteCountFormatter.string(fromByteCount: bytes + reserve, countStyle: .file)) boş alan gerekiyor.")
        }
    }
}
