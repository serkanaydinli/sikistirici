import Foundation
import Darwin

public final class OperationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    public init() { }
    public func cancel() {
        lock.lock(); cancelled = true; let active = process; lock.unlock()
        if let active, active.isRunning { active.terminate() }
    }
    public func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw ArchiveFailure.cancelled }
    }
    func attach(_ value: Process) throws {
        lock.lock(); process = value; let stop = cancelled; lock.unlock()
        if stop { if value.isRunning { value.terminate() }; throw ArchiveFailure.cancelled }
    }
    func detach() { lock.lock(); process = nil; lock.unlock() }
}

private final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var exceeded = false
    let limit: Int
    init(limit: Int) { self.limit = limit }
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let room = max(0, limit - data.count)
        data.append(chunk.prefix(room))
        if chunk.count > room { exceeded = true }
    }
    var snapshot: (String, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: data, as: UTF8.self), exceeded)
    }
    var exceededLimit: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
}

struct EngineProcess {
    let executable: URL
    func run(_ arguments: [String], directory: URL? = nil, password: String? = nil, creatingPassword: Bool = false,
             control: OperationControl, progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in },
             monitor: (() throws -> Void)? = nil) throws -> String {
        try control.check()
        guard FileManager.default.fileExists(atPath: executable.path) else { throw ArchiveFailure.engine("Arşiv motoru bulunamadı. Uygulamayı yeniden derleyin.") }
        let process = Process(); let out = Pipe(); let err = Pipe(); let input = Pipe()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"; environment["LANG"] = "en_US.UTF-8"
        process.environment = environment
        process.standardOutput = out; process.standardError = err; process.standardInput = input
        let stdout = CapturedOutput(limit: 32 * 1024 * 1024)
        let stderr = CapturedOutput(limit: 512 * 1024)
        let readers = DispatchGroup()
        do { try process.run() }
        catch { throw ArchiveFailure.engine("Arşiv motoru başlatılamadı: \(error.localizedDescription)") }
        var pendingError: Error?
        do { try control.attach(process) } catch { pendingError = error }
        defer { control.detach() }
        for (handle, capture, report) in [(out.fileHandleForReading, stdout, true), (err.fileHandleForReading, stderr, false)] {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? handle.close(); readers.leave() }
                while let chunk = try? handle.read(upToCount: 16_384), !chunk.isEmpty {
                    capture.append(chunk)
                    if report {
                        let text = String(decoding: chunk, as: UTF8.self)
                        if let range = text.range(of: #"\b\d{1,3}%"#, options: .regularExpression),
                           let percent = Double(text[range].dropLast()) {
                            progress(ProgressUpdate(fraction: min(1, percent / 100), message: "İşleniyor…"))
                        }
                    }
                }
            }
        }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        if let password, !password.isEmpty {
            let value = password + "\n" + (creatingPassword ? password + "\n" : "")
            try? input.fileHandleForWriting.write(contentsOf: Data(value.utf8))
        }
        try? input.fileHandleForWriting.close()
        let started = Date(); var stopTime: Date?; var lastMonitor = Date.distantPast
        while process.isRunning {
            if pendingError == nil {
                do {
                    try control.check()
                    if Date().timeIntervalSince(started) > 20 * 60 { throw ArchiveFailure.limit("İşlem 20 dakikalık süre sınırını aştı.") }
                    if stdout.exceededLimit || stderr.exceededLimit { throw ArchiveFailure.limit("Motor çıktısı güvenli boyut sınırını aştı.") }
                    if Date().timeIntervalSince(lastMonitor) > 0.6 { try monitor?(); lastMonitor = Date() }
                } catch { pendingError = error }
            }
            if pendingError != nil {
                if stopTime == nil { process.terminate(); stopTime = Date() }
                if let stopTime, Date().timeIntervalSince(stopTime) > 0.8, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            Thread.sleep(forTimeInterval: 0.04)
        }
        process.waitUntilExit(); readers.wait()
        if let pendingError { throw pendingError }
        try control.check()
        let output = stdout.snapshot; let errorOutput = stderr.snapshot
        if output.1 || errorOutput.1 { throw ArchiveFailure.limit("Motor çıktısı güvenli boyut sınırını aştı.") }
        guard process.terminationStatus == 0 else {
            let combined = output.0 + "\n" + errorOutput.0
            if combined.localizedCaseInsensitiveContains("password") || combined.contains("Headers Error") {
                throw (password?.isEmpty == false ? ArchiveFailure.wrongPassword : ArchiveFailure.passwordRequired)
            }
            if combined.contains("No space left") { throw ArchiveFailure.engine("Diskte yeterli boş alan yok.") }
            if combined.contains("Is not archive") || combined.contains("Can not open the file as") { throw ArchiveFailure.invalidArchive("Dosya desteklenmiyor veya hasarlı.") }
            throw ArchiveFailure.engine("İşlem tamamlanamadı (kod \(process.terminationStatus)). Arşivi ve hedef klasör izinlerini kontrol edin.")
        }
        return output.0
    }
}
