import Foundation

public struct FinderRequest: Sendable {
    public enum Action: String, Sendable { case compress, extract }
    public let action: Action
    public let files: [URL]
    public init(action: Action, files: [URL]) { self.action = action; self.files = files }
    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "sikistirici",
              components.user == nil, components.password == nil, components.port == nil, components.path.isEmpty,
              let host = components.host, let action = Action(rawValue: host),
              let items = components.queryItems, items.allSatisfy({ $0.name == "file" }) else { throw ArchiveFailure.engine("Geçersiz Finder isteği.") }
        let urls = try items.map { item -> URL in
            guard let value = item.value, let file = URL(string: value), file.isFileURL, file.host == nil || file.host == "localhost", file.path.hasPrefix("/"), !file.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ArchiveFailure.engine("Finder yalnız yerel dosyalar gönderebilir.") }
            return file.standardizedFileURL
        }
        guard !urls.isEmpty, urls.count <= 500 else { throw ArchiveFailure.engine("Finder isteğinde 1–500 dosya olmalı.") }
        self.action = action; files = urls
    }
    public func encodedURL() throws -> URL {
        var components = URLComponents(); components.scheme = "sikistirici"; components.host = action.rawValue
        components.queryItems = files.map { URLQueryItem(name: "file", value: $0.absoluteString) }
        guard let url = components.url, url.absoluteString.utf8.count <= 200_000 else { throw ArchiveFailure.engine("Finder seçimi çok büyük.") }
        _ = try FinderRequest(url: url)
        return url
    }
}
