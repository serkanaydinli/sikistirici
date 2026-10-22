import AppKit

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let document = try XMLDocument(contentsOf: url)
guard let root = document.rootElement() else { fatalError("Installer XML root missing") }
func element(_ name: String, value: String? = nil, attributes: [String: String] = [:]) -> XMLElement {
    let node = XMLElement(name: name, stringValue: value)
    for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
        node.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
    }
    return node
}
root.addChild(element("title", value: "Sıkıştırıcı"))
let resources = URL(fileURLWithPath: CommandLine.arguments[2])
let welcome = NSMutableAttributedString(string: "")
guard let image = NSImage(contentsOf: resources.appendingPathComponent("LauncherIcon.png")) else { fatalError("Installer logo missing") }
let canvasSize = NSSize(width: 620, height: 448)
let canvas = NSImage(size: canvasSize)
canvas.lockFocus()
image.draw(in: NSRect(x: 32, y: 32, width: 80, height: 80))
canvas.unlockFocus()
guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Installer background rendering failed") }
try png.write(to: resources.appendingPathComponent("installer-background.png"))
welcome.append(NSAttributedString(string: "Sıkıştırıcı\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 23)]))
welcome.append(NSAttributedString(string: "Az yer. Çok iş.\n\n", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
welcome.append(NSAttributedString(string: "Geliştirici: Serkan Aydınlı\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
welcome.append(NSAttributedString(string: """
Açık kaynak · MIT lisansı

Uygulamayı Uygulamalar klasörüne kurar.
Apple Silicon Mac · macOS 14 veya sonrası.
Kurulum öncesinde açık Sıkıştırıcı uygulamasını kapatın.

Beta paket imzasızdır; Apple noter onayı yoktur.
""", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
let rtf = try welcome.data(from: NSRange(location: 0, length: welcome.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
try rtf.write(to: resources.appendingPathComponent("welcome.rtf"))
root.addChild(element("welcome", attributes: ["file": "welcome.rtf"]))
for name in ["background", "background-darkAqua"] {
    root.addChild(element(name, attributes: ["file": "installer-background.png", "alignment": "bottomleft", "scaling": "none"]))
}
root.addChild(element("conclusion", attributes: ["file": "conclusion.html", "mime-type": "text/html"]))
if let options = root.elements(forName: "options").first {
    options.addAttribute(XMLNode.attribute(withName: "hostArchitectures", stringValue: "arm64") as! XMLNode)
    options.addAttribute(XMLNode.attribute(withName: "customize", stringValue: "never") as! XMLNode)
}
let allowed = element("allowed-os-versions")
allowed.addChild(element("os-version", attributes: ["min": "14.0"]))
root.addChild(allowed)
root.addChild(element("domains", attributes: ["enable_anywhere": "false", "enable_currentUserHome": "false", "enable_localSystem": "true"]))
for choice in root.elements(forName: "choice") where choice.attribute(forName: "id")?.stringValue == "local.sikistirici.installer" {
    choice.addAttribute(XMLNode.attribute(withName: "title", stringValue: "Sıkıştırıcı") as! XMLNode)
}
try document.xmlData(options: .nodePrettyPrint).write(to: url, options: .atomic)
