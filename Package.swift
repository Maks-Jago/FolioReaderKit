// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FolioReaderKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "FolioReaderKit",
            targets: ["FolioReaderKit"]),
    ],
    dependencies: [
        .package(name: "ZipArchive", url: "https://github.com/Maks-Jago/ZipArchive.git", .branch("master")),
        .package(name: "MenuItemKit", url: "https://github.com/cxa/MenuItemKit.git", .exact("4.0.1")),
        .package(name: "ZFDragableModalTransition", url: "https://github.com/Maks-Jago/ZFDragableModalTransition.git", .branch("master")),
        .package(name: "AEXML", url: "https://github.com/tadija/AEXML.git", from: "4.2.2"),
        .package(name: "FontBlaster", url: "https://github.com/ArtSabintsev/FontBlaster.git", .exact("5.1.1")),
        .package(name: "Realm", url: "https://github.com/realm/realm-cocoa.git", .exact("3.12.0"))
    ],
    targets: [
        .target(
            name: "FolioReaderKit",
            dependencies: [
                "ZipArchive",
                "MenuItemKit",
                "ZFDragableModalTransition",
                "AEXML",
                "FontBlaster",
                "Realm"
            ],
            path: "Source"
        ),
    ]
)
