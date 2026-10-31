// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Guiyu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Guiyu", targets: ["Guiyu"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.6.1"),
                   .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "Guiyu",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), .product(name:"Sparkle", package:"Sparkle")],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("SwiftUI"), .linkedFramework("AppKit"), .linkedFramework("PDFKit"), .linkedFramework("QuickLookUI"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])
    ])
