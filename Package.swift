// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let cssFiles: [String] = {
    let fm = FileManager.default
    let sourcesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Sources/mechasqueak")
    guard let enumerator = fm.enumerator(
        at: sourcesDir,
        includingPropertiesForKeys: nil
    ) else { return [] }
    var result: [String] = []
    while let url = enumerator.nextObject() as? URL {
        if url.pathExtension == "css" {
            result.append(url.path.replacingOccurrences(
                of: sourcesDir.path + "/", with: ""))
        }
    }
    return result
}()

let package = Package(
    name: "mechasqueak",
    platforms: [
        .macOS("14.0")
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/supermanifolds/Lingo.git", from: Version(4, 0, 0)),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: Version(1, 33, 1)),
        .package(url: "https://github.com/apple/swift-nio.git", from: Version(2, 97, 1)),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: Version(2, 36, 1)),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: Version(1, 33, 0)),
        .package(url: "https://github.com/crossroadlabs/Regex.git", from: Version(1, 2, 0)),
        .package(url: "https://github.com/mattpolzin/JSONAPI.git", from: Version(6, 0, 0)),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: Version(1, 9, 0)),
        .package(url: "https://github.com/vapor/sql-kit.git", from: Version(3, 35, 0)),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: Version(2, 15, 1)),
        .package(url: "https://github.com/vapor/sqlite-kit.git", from: Version(4, 5, 2)),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: Version(0, 15, 1)),
        .package(url: "https://github.com/swift-server/swift-backtrace.git", from: Version(1, 3, 5)),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: Version(2, 16, 2)),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor-community/HTMLKit.git", branch: "main"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: Version(0, 63, 2)),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        .package(path: "../IRCKit")
        //.package(name: "IRCKit", url: "https://github.com/FuelRats/IRCKit.git", from: Version(0, 15, 0))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .executableTarget(
            name: "mechasqueak",
            dependencies: [
                .product(name: "Lingo", package: "Lingo"),
                "CryptoSwift",
                "Stencil",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "Regex", package: "Regex"),
                .product(name: "JSONAPI", package: "JSONAPI"),
                .product(name: "IRCKit", package: "IRCKit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "SQLiteKit", package: "sqlite-kit"),
                .product(name: "Backtrace", package: "swift-backtrace"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "HTMLKit", package: "HTMLKit"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            exclude: cssFiles,
            swiftSettings: [.swiftLanguageMode(.v5)]
            //plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "mechasqueakTests",
            dependencies: ["mechasqueak"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
