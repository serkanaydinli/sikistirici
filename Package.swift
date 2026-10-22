// swift-tools-version: 6.0
import PackageDescription
import Foundation
let vendorLibrary = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Vendor/libarchive/lib/libarchive.a").path

let package = Package(
    name: "Sikistirici",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sikistirici", targets: ["SikistiriciApp"])],
    targets: [
        .target(name:"CArchivePreview",cSettings:[.headerSearchPath("../../Vendor/libarchive/include")],linkerSettings:[.unsafeFlags([vendorLibrary]),.linkedLibrary("z"),.linkedLibrary("bz2"),.linkedLibrary("lzma"),.linkedLibrary("iconv")]),
        .target(name: "ArchiveCore",dependencies:["CArchivePreview"]),
        .executableTarget(name: "SikistiriciApp", dependencies: ["ArchiveCore"], resources: [.copy("Resources")]),
        .testTarget(name: "ArchiveCoreTests", dependencies: ["ArchiveCore", "SikistiriciApp"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
