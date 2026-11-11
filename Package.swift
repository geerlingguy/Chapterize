// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Chapterize",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Chapterize", targets: ["Chapterize"]),
        .executable(name: "chapterize-cli", targets: ["chapterize-cli"]),
    ],
    targets: [
        .target(name: "ChapterCore"),
        .executableTarget(name: "Chapterize", dependencies: ["ChapterCore"]),
        .executableTarget(name: "chapterize-cli", dependencies: ["ChapterCore"]),
    ],
    swiftLanguageModes: [.v5]
)
