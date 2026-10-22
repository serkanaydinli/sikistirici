import Foundation
import CArchivePreview

private final class PreviewContext {
    let control: OperationControl
    let deadline = Date().addingTimeInterval(15)
    var entries: [ArchiveEntry] = []
    var error: Error?
    init(control: OperationControl) { self.control = control }
}

public enum NativePreviewReader {
    public static func list(_ url: URL, control: OperationControl = OperationControl()) throws -> ArchiveContents {
        try control.check()
        let context = PreviewContext(control:control)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        var message = [CChar](repeating:0,count:1024)
        let status = sa_preview_list(url.path,100_000,{ path,size,directory,link,encrypted,opaque in
            guard let opaque, let path else { return 0 }
            let context = Unmanaged<PreviewContext>.fromOpaque(opaque).takeUnretainedValue()
            do {
                try context.control.check()
                guard Date() < context.deadline else { throw ArchiveFailure.limit("Önizleme süre sınırına ulaştı. Arşivi Sıkıştırıcı’da aç.") }
                var name = String(cString:path)
                while name.hasSuffix("/") { name.removeLast() }
                context.entries.append(ArchiveEntry(path:name,size:max(0,size),isDirectory:directory != 0,isLink:link != 0,encrypted:encrypted != 0))
                return 1
            } catch { context.error = error; return 0 }
        },pointer,&message,message.count)
        if let error = context.error { throw error }
        guard status == 0 else {
            if status == -3 { throw ArchiveFailure.limit("Arşivde 100.000’den fazla girdi var.") }
            let message = String(cString:message)
            if message.localizedCaseInsensitiveContains("encrypt") || message.localizedCaseInsensitiveContains("passphrase") || message.localizedCaseInsensitiveContains("password") { throw ArchiveFailure.passwordRequired }
            throw ArchiveFailure.invalidArchive("Önizleme hazırlanamadı: " + String(message.prefix(200)))
        }
        try SafetyPolicy().validate(context.entries)
        return ArchiveContents(entries:context.entries)
    }
}
