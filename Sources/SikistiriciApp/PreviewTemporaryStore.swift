import Foundation
import Darwin

/// Owns transient plaintext previews. The lock stays held until every operation
/// retaining this store has finished, so another app instance cannot erase it.
final class PreviewTemporaryStore: @unchecked Sendable {
    let baseURL: URL
    let sessionURL: URL
    private let lockFD: Int32
    private let sessionDevice: dev_t
    private let sessionInode: ino_t

    init(temporaryRoot: URL = FileManager.default.temporaryDirectory) throws {
        baseURL = temporaryRoot.appendingPathComponent("SikistiriciPreviews-v1", isDirectory: true)
        if mkdir(baseURL.path, 0o700) != 0 && errno != EEXIST { throw Self.posixError() }
        let base = open(baseURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard base >= 0 else { throw Self.posixError() }
        defer { close(base) }
        var baseInfo = stat()
        guard fstat(base, &baseInfo) == 0, baseInfo.st_uid == geteuid(),
              (baseInfo.st_mode & S_IFMT) == S_IFDIR else { throw Self.denied() }
        guard fchmod(base, 0o700) == 0 else { throw Self.posixError() }
        // Serialize cleanup with session creation. Otherwise another instance
        // could acquire a just-created session lock before its creator does.
        var indexLock = openat(base, ".sessions.lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if indexLock < 0 && errno == EEXIST {
            indexLock = openat(base, ".sessions.lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        }
        guard indexLock >= 0 else { throw Self.posixError() }
        defer { close(indexLock) }
        var indexInfo = stat()
        guard fstat(indexLock, &indexInfo) == 0, indexInfo.st_uid == geteuid(),
              (indexInfo.st_mode & S_IFMT) == S_IFREG, indexInfo.st_nlink == 1 else { throw Self.denied() }
        guard flock(indexLock, LOCK_EX) == 0 else { throw Self.posixError() }
        Self.cleanOrphans(baseURL: baseURL, baseFD: base)
        let name = "session-\(UUID())"
        sessionURL = baseURL.appendingPathComponent(name, isDirectory: true)
        guard mkdirat(base, name, 0o700) == 0 else { throw Self.posixError() }
        let session = openat(base, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard session >= 0 else { throw Self.posixError() }
        defer { close(session) }
        var sessionInfo = stat()
        guard fstat(session, &sessionInfo) == 0, sessionInfo.st_uid == geteuid() else { throw Self.denied() }
        let lock = openat(session, ".lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Self.posixError() }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw Self.posixError() }
        lockFD = lock
        sessionDevice = sessionInfo.st_dev
        sessionInode = sessionInfo.st_ino
    }
    deinit {
        Self.removeOwnedDirectory(sessionURL, device: sessionDevice, inode: sessionInode)
        close(lockFD)
    }
    func makePreviewDirectory() throws -> URL {
        let name = "preview-\(UUID())"
        let url = sessionURL.appendingPathComponent(name, isDirectory: true)
        let session = open(sessionURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard session >= 0 else { throw Self.posixError() }
        defer { close(session) }
        var info = stat()
        guard fstat(session, &info) == 0, info.st_uid == geteuid(),
              info.st_dev == sessionDevice, info.st_ino == sessionInode else { throw Self.denied() }
        guard mkdirat(session, name, 0o700) == 0 else { throw Self.posixError() }
        return url
    }
    func removePreview(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == sessionURL.standardizedFileURL,
              Self.isUUIDName(url.lastPathComponent, prefix: "preview-") else { return }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        Self.removeOwnedDirectory(url, device: info.st_dev, inode: info.st_ino)
    }
    private static func cleanOrphans(baseURL: URL, baseFD: Int32) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: baseURL.path) else { return }
        for name in names where isUUIDName(name, prefix: "session-") {
            let session = openat(baseFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard session >= 0 else { continue }
            defer { close(session) }
            var info = stat()
            guard fstat(session, &info) == 0, info.st_uid == geteuid(), (info.st_mode & 0o077) == 0 else { continue }
            let lock = openat(session, ".lock", O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            // Missing locks can be an instance still creating its session. Leave
            // them alone rather than race startup or remove an unknown folder.
            guard lock >= 0 else { continue }
            defer { close(lock) }
            var lockInfo = stat()
            guard fstat(lock, &lockInfo) == 0, lockInfo.st_uid == geteuid(),
                  (lockInfo.st_mode & S_IFMT) == S_IFREG, lockInfo.st_nlink == 1,
                  flock(lock, LOCK_EX | LOCK_NB) == 0 else { continue }
            removeOwnedDirectory(baseURL.appendingPathComponent(name), device: info.st_dev, inode: info.st_ino)
        }
    }
    private static func removeOwnedDirectory(_ url: URL, device: dev_t, inode: ino_t) {
        var current = stat()
        guard lstat(url.path, &current) == 0, current.st_uid == geteuid(),
              (current.st_mode & S_IFMT) == S_IFDIR,
              current.st_dev == device, current.st_ino == inode else { return }
        // FileManager unlinks contained symlinks rather than following targets.
        try? FileManager.default.removeItem(at: url)
    }
    private static func isUUIDName(_ name: String, prefix: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        return UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }
    private static func posixError() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private static func denied() -> Error { NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
}
