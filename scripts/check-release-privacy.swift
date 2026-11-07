import Foundation

let app = URL(fileURLWithPath: CommandLine.arguments[1])
let executables = ["Contents/MacOS/Sikistirici", "Contents/Resources/7zz",
    "Contents/PlugIns/SikistiriciFinder.appex/Contents/MacOS/SikistiriciFinder",
    "Contents/PlugIns/SikistiriciPreview.appex/Contents/MacOS/SikistiriciPreview"]
for relative in executables {
    let data = try Data(contentsOf: app.appendingPathComponent(relative))
    guard data.range(of: Data("/Users/".utf8)) == nil else {
        // Never print the embedded private path itself.
        fputs("Release privacy check failed: local user path in \(relative)\n", stderr)
        exit(1)
    }
}
print("Release privacy check passed: no local user paths in shipped executables.")
