//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(Essentials) @_spi(ProtocolProvider) import SwiftNetwork
import Dispatch

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

// MARK: - IP address parsing

@available(Network 0.1.0, *)
func parseIPv4(_ string: String) -> IPv4Address? {
    let parts = string.split(separator: ".")
    guard parts.count == 4 else { return nil }
    var bytes = [UInt8]()
    for part in parts {
        guard let value = UInt8(part) else { return nil }
        bytes.append(value)
    }
    return IPv4Address(bytes)
}

@available(Network 0.1.0, *)
func parseIPv6(_ string: String) -> IPv6Address? {
    var addr = in6_addr()
    guard string.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else {
        return nil
    }
    let bytes = withUnsafeBytes(of: &addr) { Array($0) }
    return IPv6Address(bytes)
}

// MARK: - Helpers

@available(Network 0.1.0, *)
func makeParams(localEndpoint: Endpoint) -> ParametersBuilder<UDP> {
    let builder = ParametersBuilder<UDP>.parameters { UDP() }
        .localEndpoint(localEndpoint)
    return builder
}

@available(Network 0.1.0, *)
func makeConnection(to remote: Endpoint, localEndpoint: Endpoint) -> NetworkConnection<UDP> {
    NetworkConnection(to: remote, using: makeParams(localEndpoint: localEndpoint))
}

@available(Network 0.1.0, *)
func parseEndpoints(ipString: String, port: UInt16, localPort: UInt16) -> (remote: Endpoint, local: Endpoint)? {
    if let v4 = parseIPv4(ipString) {
        return (
            Endpoint(address: v4, port: port),
            Endpoint(address: IPv4Address.loopback, port: localPort)
        )
    } else if let v6 = parseIPv6(ipString) {
        return (
            Endpoint(address: v6, port: port),
            Endpoint(address: IPv6Address.loopback, port: localPort)
        )
    }
    return nil
}

// MARK: - SocketTransfer

@available(Network 0.1.0, *)
final class SocketTransfer {

    static let NSEC_PER_MSEC = UInt64(Duration.milliseconds(1) / Duration.nanoseconds(1))

    let clientPort: UInt16 = 9100
    let serverPort: UInt16 = 9101

    func run(iterations: Int, sendSize: Int, echo: Bool) -> Double {
        let clientLocal = Endpoint(address: IPv4Address.loopback, port: clientPort)
        let clientRemote = Endpoint(address: IPv4Address.loopback, port: serverPort)
        let serverLocal = Endpoint(address: IPv4Address.loopback, port: serverPort)
        let serverRemote = Endpoint(address: IPv4Address.loopback, port: clientPort)

        let payload = (0..<sendSize).map { _ in UInt8.random(in: 0...255) }
        nonisolated(unsafe) var successCount = 0
        let mode = echo ? "round-trip echo" : "one-way send"
        print("Running Socket \(mode), transferring \(iterations) datagram\(iterations > 1 ? "s" : "")")
        let timestart = DispatchTime.now().uptimeNanoseconds

        let group = DispatchGroup()
        group.enter()

        let client = makeConnection(to: clientRemote, localEndpoint: clientLocal)
        let server = makeConnection(to: serverRemote, localEndpoint: serverLocal)

        nonisolated(unsafe) let done = { [group] in
            client.cancel()
            server.cancel()
            group.leave()
        }

        client.start()
        server.start()

        if echo {
            @Sendable func echoIteration(_ i: Int) {
                guard i < iterations else {
                    done()
                    return
                }

                client.send(.message(content: payload)) { result in
                    if case .failure(let error) = result {
                        print("Client send failed at \(i): \(error)")
                        done()
                        return
                    }
                }

                server.receive { result in
                    guard case .success(let msg) = result else {
                        print("Server receive failed at \(i)")
                        done()
                        return
                    }

                    server.send(.message(content: msg.content)) { result in
                        if case .failure(let error) = result {
                            print("Server echo failed at \(i): \(error)")
                            done()
                            return
                        }
                    }

                    client.receive { result in
                        guard case .success(let echo) = result else {
                            print("Client echo receive failed at \(i)")
                            done()
                            return
                        }

                        if echo.content == payload {
                            successCount += 1
                        } else {
                            print("Echo mismatch at \(i)")
                        }
                        echoIteration(i + 1)
                    }
                }
            }
            echoIteration(0)
        } else {
            for i in 0..<iterations {
                let sem = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var failed = false
                client.send(.message(content: payload)) { result in
                    if case .failure = result { failed = true }
                    sem.signal()
                }
                sem.wait()
                if failed {
                    print("Client send failed at \(i)")
                    break
                }
                successCount += 1
            }
            done()
        }

        group.wait()
        print("Completed \(successCount) / \(iterations) transfers")
        guard successCount == iterations else { return 0 }
        let endTime = DispatchTime.now().uptimeNanoseconds
        return Double(endTime - timestart) / Double(SocketTransfer.NSEC_PER_MSEC) / 1000.0
    }

    func sendToRemote(
        ipString: String,
        port: UInt16,
        localPort: UInt16,
        iterations: Int,
        sendSize: Int
    ) -> Double {
        guard let endpoints = parseEndpoints(ipString: ipString, port: port, localPort: localPort) else {
            print("Invalid IP address: \(ipString)")
            return 0
        }

        let payload = (0..<sendSize).map { _ in UInt8.random(in: 0...255) }
        var successCount = 0
        print("Sending \(iterations) datagram\(iterations > 1 ? "s" : "") to \(ipString):\(port)")
        let timestart = DispatchTime.now().uptimeNanoseconds

        let group = DispatchGroup()
        group.enter()

        let client = makeConnection(to: endpoints.remote, localEndpoint: endpoints.local)
        client.start()

        for i in 0..<iterations {
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var failed = false
            client.send(.message(content: payload)) { result in
                if case .failure = result { failed = true }
                sem.signal()
            }
            sem.wait()
            if failed {
                print("Failed to send at iteration \(i)")
                break
            }
            successCount += 1
        }

        client.cancel()
        group.leave()
        group.wait()

        print("Completed \(successCount) / \(iterations) sends")
        guard successCount == iterations else { return 0 }
        let endTime = DispatchTime.now().uptimeNanoseconds
        return Double(endTime - timestart) / Double(SocketTransfer.NSEC_PER_MSEC) / 1000.0
    }
}

// MARK: - Argument parsing helper

func parseArg<T>(_ arguments: [String], _ flag: String, parse: (String) -> T?) -> T? {
    guard let index = arguments.firstIndex(of: flag),
        arguments.count > index + 1
    else { return nil }
    return parse(arguments[index + 1])
}

if #available(anyAppleOS 26, *) {
    // MARK: - Argument parsing

    var iterations = 100
    var sendSize = 1000
    var echo = true
    var remoteIP: String? = nil
    var remotePort: UInt16? = nil
    var localPort: UInt16 = 0
    let arguments = CommandLine.arguments

    if let v: Int = parseArg(arguments, "-iterations", parse: { Int($0) }) { iterations = v }
    if let v: Int = parseArg(arguments, "-size", parse: { Int($0) }) { sendSize = v }
    if let v: String = parseArg(arguments, "-ip", parse: { $0 }) { remoteIP = v }
    if let v: UInt16 = parseArg(arguments, "-port", parse: { UInt16($0) }) { remotePort = v }
    if let v: UInt16 = parseArg(arguments, "-localport", parse: { UInt16($0) }) { localPort = v }
    if arguments.contains("-oneway") { echo = false }

    // MARK: - Run

    let socketTransfer = SocketTransfer()

    if let remoteIP {
        guard let remotePort else {
            print("Error: -port is required when using -ip")
            exit(1)
        }
        print("Starting \(iterations) sends to \(remoteIP):\(remotePort)")
        let totalTime = socketTransfer.sendToRemote(
            ipString: remoteIP,
            port: remotePort,
            localPort: localPort,
            iterations: iterations,
            sendSize: sendSize
        )
        if totalTime > 0 {
            print("Finished all (\(iterations)) sends in \(totalTime) seconds")
        } else {
            print("Error running all (\(iterations)) sends, something failed")
        }
    } else {
        let mode = echo ? "round-trip echo" : "one-way send"
        print("Starting \(iterations) \(mode) transfers")
        let totalTime = socketTransfer.run(iterations: iterations, sendSize: sendSize, echo: echo)
        if totalTime > 0 {
            print("Finished all (\(iterations)) transfers in \(totalTime) seconds")
        } else {
            print("Error running all (\(iterations)) transfers, something failed")
        }
    }
} else {
    fatalError("This tool requires macOS 26 or newer")
}
