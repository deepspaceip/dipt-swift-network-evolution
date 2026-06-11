// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

var packageDependencies = [PackageDescription.Package.Dependency]()
var targetDependencies = [PackageDescription.Target.Dependency]()

// Logging levels, qlog output, and QUIC signposts are configured via package
// traits. See the `traits:` list on the `Package(...)` initializer below.
var settings: [SwiftSetting] = [
    .define("IMPORT_SWIFTTLS"),
    .define("EXPORT_SWIFTTLS"),
    .define("IMPORT_CRYPTO"),
    .define("SWIFTTLS_CERTIFICATE_VERIFICATION"),
    .unsafeFlags(["-Xfrontend", "-experimental-spi-only-imports"]),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("ExistentialAny"),
]

#if os(Linux)
packageDependencies = [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0-beta.1"),
    .package(url: "https://github.com/apple/swift-tls.git", branch: "main"),
]
targetDependencies = [
    .product(name: "Logging", package: "swift-log"),
    .target(name: "SwiftNetworkLinuxShim", condition: .when(platforms: [.linux])),
    .product(name: "DequeModule", package: "swift-collections"),
    .product(name: "BasicContainers", package: "swift-collections"),
    .product(name: "Crypto", package: "swift-crypto"),
    .product(name: "CryptoExtras", package: "swift-crypto"),
    .product(name: "SwiftTLS", package: "swift-tls"),
]
#else
packageDependencies = [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0-beta.1"),
    .package(url: "https://github.com/apple/swift-tls.git", branch: "main"),
]
targetDependencies = [
    .product(name: "DequeModule", package: "swift-collections"),
    .product(name: "BasicContainers", package: "swift-collections"),
    .product(name: "Crypto", package: "swift-crypto"),
    .product(name: "CryptoExtras", package: "swift-crypto"),
    .product(name: "SwiftTLS", package: "swift-tls"),
]

// To support back to macOS 26, provide a shim on top of crypto APIs
// that allows passing spans. This is a less performant path, so for
// performance-sensitive cases, remove this define and require at least
// macOS 27.
settings.append(.define("SHIM_CRYPTO_SPAN_APIS"))
#endif

let package = Package(
    name: "swift-network-evolution",
    products: [
        .library(
            name: "SwiftNetwork",
            targets: ["SwiftNetwork"]
        ),
        .library(
            name: "SwiftNetworkBenchmarks",
            targets: ["SwiftNetworkBenchmarks"]
        ),
    ],
    traits: [
        .trait(
            name: "DisableDebugLogging",
            description: "Disables the `debug` and `info` logging levels."
        ),
        .trait(
            name: "DisableErrorLogging",
            description: "Disables the `error`, `notice`, and `fault` logging levels."
        ),
        .trait(
            name: "DatapathLogging",
            description:
                "Enables the verbose `datapath` logging level (requires that `DisableDebugLogging` is not enabled)."
        ),
        .trait(
            name: "QlogOutput",
            description: "Enables qlog output from the QUIC implementation."
        ),
        .trait(
            name: "SignpostOutput",
            description: "Enables `OSSignposter` output from the QUIC implementation."
        ),
        .default(enabledTraits: []),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "SwiftNetwork",
            dependencies: targetDependencies,
            swiftSettings: settings
        ),
        .target(
            name: "SwiftNetworkLinuxShim",
            dependencies: [],
            cSettings: [
                .define("_GNU_SOURCE")
            ],
            swiftSettings: settings
        ),
        .target(
            name: "SwiftNetworkBenchmarks",
            dependencies: targetDependencies + ["SwiftNetwork"],
            swiftSettings: settings
        ),
        .testTarget(
            name: "SwiftNetworkTests",
            dependencies: ["SwiftNetwork"],
            swiftSettings: settings
        ),
        .testTarget(
            name: "QUICTests",
            dependencies: ["SwiftNetwork"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "QUICHandshake",
            dependencies: ["SwiftNetwork", "SwiftNetworkBenchmarks"],
            path: "Sources/Tools/QUICHandshake",
            exclude: ["README.md"],
            swiftSettings: settings,
        ),
        .executableTarget(
            name: "IPUDPTransfer",
            dependencies: ["SwiftNetwork", "SwiftNetworkBenchmarks"],
            path: "Sources/Tools/IPUDPTransfer",
            exclude: ["README.md"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "QUICTransfer",
            dependencies: ["SwiftNetwork", "SwiftNetworkBenchmarks"],
            path: "Sources/Tools/QUICTransfer",
            exclude: ["README.md"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "QUICStreamLoad",
            dependencies: ["SwiftNetwork", "SwiftNetworkBenchmarks"],
            path: "Sources/Tools/QUICStreamLoad",
            exclude: ["README.md"],
            swiftSettings: settings
        ),
        .executableTarget(
            name: "SocketTransfer",
            dependencies: ["SwiftNetwork", "SwiftNetworkBenchmarks"],
            path: "Sources/Tools/SocketTransfer",
            exclude: ["README.md"],
            swiftSettings: settings
        ),
    ]
)
