#  Swift Network Evolution

The Network framework provides implementations of transport protocols, such as QUIC, along with types used to communicate network endpoints (like IP addresses) and various parameters and preferences for how to set up transport connections.

This package provides access to the implementations of core networking objects and protocol stack architecture from [Network.framework](https://developer.apple.com/documentation/network) that is available on Apple platforms. This package is intended to be used by cross-platform projects like [SwiftNIO](https://github.com/apple/swift-nio) to be able to access a Swift-based implementation of protocols like QUIC.

On macOS, iOS, and other Apple platforms, apps should use the Network.framework that comes with the operating system.

> [!NOTE]
> At this time, all types exposed in this package are marked as SPI and subject to change at any time.
> There are no support guarantees that can be made until these SPIs transition to stable APIs at a later date.

## Building and Testing

> [!NOTE]
> Building this package requires the Swift 6.3 toolchain or later. You can download toolchains from [the Swift website](https://swift.org/install).

To build via the command line (for all platforms), run `swift build` at the root of package.

To run all unit tests, run `swift test`. Unit tests can also be run by filtering a specific class or function:

```
% swift test --filter SwiftNetworkUDPTests
% swift test --filter SwiftNetworkUDPTests.testUDPEcho
```

All unit tests are run automatically upon creation or update of a Pull Request. See [CONTRIBUTING](https://github.com/apple/swift-network-evolution/blob/main/CONTRIBUTING.md) for details.

### Logging Levels

By default, Swift Network will emit logs at `debug`, `info`, `notice`, `error`, and `fault` levels. There are also datapath-specific debug logs, referred to as `datapath` logs, that are disabled by default.

Logging configuration is exposed via [package traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md):

| Trait | Default | Effect |
|---|---|---|
| `DisableDebugLogging` | not specified | When specified, compiles out the `debug` and `info` logging levels. |
| `DisableErrorLogging` | not specified | When specified, compiles out the `error`, `notice`, and `fault` logging levels. |
| `DatapathLogging` | not specified | When specified, compiles in the verbose `datapath` logging level. Has no effect if `DisableDebugLogging` is also specified. |

The level traits are expressed as suppression flags so that they compose well across a dependency graph. SwiftPM unifies trait selections by union, so a leaf package can always specify a `*Disabled` trait to suppress a level that an intermediate left compiled in, but cannot re-introduce a level that an intermediate suppressed.

Intermediate libraries that depend on Swift Network should therefore not modify the default trait set when declaring the dependency. Specifying `DisableDebugLogging` or `DisableErrorLogging` in a library's `Package.swift` would force the corresponding levels to be suppressed for every leaf application that consumes the library, regardless of what those leaves want. The choice belongs to the leaf, where the deployment context is known.

A dependent package opts in to suppression when declaring the dependency, e.g. to compile out all logging:

```swift
.package(
    url: "https://github.com/apple/swift-network-evolution",
    branch: "main",
    traits: ["DisableDebugLogging", "DisableErrorLogging"]
)
```

When building this package directly, the `swift` CLI accepts the same traits:

```
swift test --traits DisableDebugLogging,DisableErrorLogging
```

### QUIC Logs

QUIC log output in the [qlog](https://datatracker.ietf.org/doc/draft-ietf-quic-qlog-main-schema/) format is controlled by the `QlogOutput` trait, and `os_signpost` output by `SignpostOutput`. Both are *positive* traits and neither is in the default trait set, so qlog and signpost code is compiled out by default.

Either feature is enabled by specifying the trait when declaring the dependency:

```swift
.package(
    url: "https://github.com/apple/swift-network-evolution",
    branch: "main",
    traits: ["QlogOutput", "SignpostOutput"]
)
```

For builds driven by Xcode rather than SwiftPM, add the equivalent compilation condition to the relevant xcconfig:

```
OTHER_SWIFT_FLAGS = $(inherited) -DQlogOutput -DSignpostOutput
```

When building or running this package directly from the `swift` CLI, the same trait names are accepted via `--traits`:

```
swift build --traits QlogOutput,SignpostOutput
swift test --traits QlogOutput
swift run --traits QlogOutput QUICHandshake
```

Trait composition is by union across the dependency graph, so once any package in the chain enables `QlogOutput` or `SignpostOutput`, every other package consuming Swift Network through that graph will also be built with the trait specified. A leaf package cannot suppress qlog or signpost output that an intermediate dependency turned on.

Intermediate libraries should not specify `QlogOutput` or `SignpostOutput` on their Swift Network dependency. These are diagnostic features which incur a performance cost; the decision to enable them belongs to the leaf or to test and benchmark targets that need the output.

## Performance Benchmarking Tools

This package builds several tools that can be used for benchmarking performance.

- `IPUDPTransfer` measures processing UDP/IP packets through the stack, for packet/second metrics.
- `QUICHandshake` measures parallel QUIC handshakes, for handshake/second metrics.
- `QUICStreamLoad` measures parallel data transfers over parallel QUIC streams, for requests/second metrics.
- `QUICTransfer` measures large data transfers over single QUIC streams, for throughput metrics.

## Contributions

Swift Network welcomes contributions from the community, including bug fixes, tests, documentation, and ports to new platforms. Note that this project currently has a limited scope and is focused on supporting specific projects, such as supporting QUIC in SwiftNIO.

Please use [GitHub Issues](https://github.com/apple/swift-network-evolution/issues) for tracking bugs, feature requests, and other work.

Please see the [CONTRIBUTING](https://github.com/apple/swift-network-evolution/blob/main/CONTRIBUTING.md) document for information on how to contribute to the project.
