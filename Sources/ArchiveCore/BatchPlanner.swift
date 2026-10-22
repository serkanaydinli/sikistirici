import Foundation

public enum BatchMode: String, CaseIterable, Sendable { case compress, extract }
public struct BatchItem: Sendable {
    public let source: URL
    public let destination: URL
}
public enum BatchPlanner {
    public static func plan(inputs: [URL], destination: URL, mode: BatchMode, format: ArchiveFormat = .zip) throws -> [BatchItem] {
        guard !inputs.isEmpty, inputs.count <= 500 else { throw ArchiveFailure.engine("1 ile 500 arasında kaynak seç.") }
        var occupied = Set<String>(); var seen = Set<URL>(); var result: [BatchItem] = []
        for input in inputs {
            let source = mode == .extract ? try VolumeSet.resolve(input) : input
            guard seen.insert(source.standardizedFileURL).inserted else { continue }
            let base = mode == .extract ? archiveName(source) : source.lastPathComponent
            var index = 1
            var output: URL
            repeat {
                let suffix = index == 1 ? "" : " (\(index))"
                let name = base + suffix + (mode == .compress ? "." + format.rawValue : "")
                output = destination.appendingPathComponent(name)
                index += 1
            } while occupied.contains(output.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()) || FilePublisher.exists(output)
            occupied.insert(output.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased())
            result.append(BatchItem(source: source, destination: output))
        }
        return result
    }
    public static func archiveName(_ url: URL) -> String {
        var name = url.lastPathComponent
        if name.range(of: #"\.\d{3,}$"#, options: .regularExpression) != nil { name = (name as NSString).deletingPathExtension }
        if let range = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression,.caseInsensitive]) { return String(name[..<range.lowerBound]) }
        return (name as NSString).deletingPathExtension
    }
}
