import Cocoa
import QuickLookUI


@objc(SikistiriciPreviewController)
final class SikistiriciPreviewController: NSViewController, QLPreviewingController, NSTableViewDataSource, NSTableViewDelegate {
    private var entries: [ArchiveEntry] = []
    private let table = NSTableView()
    private let heading = NSTextField(labelWithString:"Sıkıştırıcı")
    private let detail = NSTextField(labelWithString:"Arşiv içeriği okunuyor…")
    private var control = OperationControl()
    private var requestToken = UUID()
    override func loadView() {
        view = NSView(frame:NSRect(x:0,y:0,width:760,height:540))
        preferredContentSize = NSSize(width:760,height:540)
        heading.font = .systemFont(ofSize:20,weight:.semibold)
        detail.font = .systemFont(ofSize:12); detail.textColor = .secondaryLabelColor
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        for (id,title,width) in [("path","Ad",550.0),("size","Boyut",130.0)] { let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column) }
        table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 26
        scroll.documentView = table
        let stack = NSStackView(views:[heading,detail,scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:20),stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-20),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:300)])
    }
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        loadViewIfNeeded(); heading.stringValue = url.lastPathComponent
        control.cancel(); let control = OperationControl(); self.control = control
        let token = UUID(); requestToken = token
        entries = []; table.reloadData(); detail.stringValue = "Arşiv içeriği okunuyor…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            guard let self else { handler(nil); return }
            let result = Result { try NativePreviewReader.list(url,control:control) }
            DispatchQueue.main.async {
                guard token == self.requestToken else { handler(NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError)); return }
                switch result {
                case .success(let contents):
                    self.entries = Array(contents.entries.prefix(5000))
                    self.detail.stringValue = "\(contents.entries.count) girdi · \(ByteCountFormatter.string(fromByteCount:contents.totalSize,countStyle:.file)) açılmış boyut" + (contents.entries.count > 5000 ? " · ilk 5.000 gösteriliyor":"")
                    self.table.reloadData()
                case .failure(let error): self.detail.stringValue = error.localizedDescription
                }
                handler(nil)
            }
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let entry = entries[row]
        let field = NSTextField(labelWithString:tableColumn?.identifier.rawValue == "size" ? (entry.isDirectory ? "—":ByteCountFormatter.string(fromByteCount:entry.size,countStyle:.file)):(entry.isDirectory ? "▸ ":"") + entry.path)
        field.lineBreakMode = .byTruncatingMiddle; field.toolTip = entry.path; field.font = .systemFont(ofSize:12)
        return field
    }
    deinit { control.cancel() }
}
