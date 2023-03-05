// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mechasqueak",
    platforms: [
        .macOS("12.0")
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/xlexi/Lingo.git", from: Version(3, 0, 6)),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: Version(1, 10, 0)),
        .package(url: "https://github.com/apple/swift-nio.git", from: Version(2, 32, 3)),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: Version (2, 15, 1)),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: Version(1, 10, 2)),
        .package(url: "https://github.com/crossroadlabs/Regex.git", from: Version(1, 2, 0)),
        .package(url: "https://github.com/mattpolzin/JSONAPI.git", from: Version(5, 0, 2)),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: Version(1, 5, 1)),
        .package(url: "https://github.com/vapor/sql-kit.git", from: Version(3, 18, 0)),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: Version(2, 6, 0)),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: Version(0, 14, 2)),
        .package(url: "https://github.com/swift-server/swift-backtrace.git", from: Version(1, 3, 1)),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: Version(2, 5, 0)),
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
                .product(name: "Backtrace", package: "swift-backtrace"),
                .product(name: "WebSocketKit", package: "websocket-kit")
            ]
        ),
        .testTarget(
            name: "mechasqueakTests",
            dependencies: ["mechasqueak"]),
    ]
)
