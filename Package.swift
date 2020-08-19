// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "FolioReaderKit",
	dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", from: "2.1.5"),
        .package(url: "https://github.com/cxa/MenuItemKit.git", from: "4.0.1"),
        .package(url: "https://github.com/zoonooz/ZFDragableModalTransition.git", from: "0.6"),
        .package(url: "https://github.com/tadija/AEXML.git", from: "4.2.2"),
        .package(url: "https://github.com/ArtSabintsev/FontBlaster.git", from: "5.1.1"),
        .package(url: "https://github.com/fantim/JSQWebViewController.git", from: "6.1.1"),
        .package(url: "https://github.com/realm/realm-cocoa.git", from: "3.17.3"),
	]
)
