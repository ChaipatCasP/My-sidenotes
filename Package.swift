// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MySideNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MySideNotes",
            path: "Sources/MySideNotes"
        )
    ]
)
