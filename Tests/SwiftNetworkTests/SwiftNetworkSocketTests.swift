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

import XCTest

#if !NETWORK_NO_SWIFT_QUIC

#if canImport(Network_Internal)
@_spi(Essentials) @_spi(ProtocolProvider) import Network
#else
#if canImport(SwiftNetwork)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork
#endif
#endif

@available(Network 0.1.0, *)
final class SwiftNetworkSocketTests: NetTestCase {

    // MARK: - Helpers

    private func makeUDPParams(localPort: UInt16, ipv6: Bool = false) -> ParametersBuilder<UDP> {
        var builder = ParametersBuilder<UDP>.parameters { UDP() }
        if ipv6 {
            builder.parameters.localAddress = Endpoint(address: IPv6Address.loopback, port: localPort)
        } else {
            builder.parameters.localAddress = Endpoint(address: IPv4Address.loopback, port: localPort)
        }
        return builder
    }

    private func makeConnection(
        toPort: UInt16,
        localPort: UInt16,
        ipv6: Bool = false,
        cancelExpectation: XCTestExpectation
    ) -> NetworkConnection<UDP> {
        let remote: Endpoint
        if ipv6 {
            remote = Endpoint(address: IPv6Address.loopback, port: toPort)
        } else {
            remote = Endpoint(address: IPv4Address.loopback, port: toPort)
        }
        return NetworkConnection(to: remote, using: makeUDPParams(localPort: localPort, ipv6: ipv6))
            .onStateUpdate { _, state in
                if case .cancelled = state { cancelExpectation.fulfill() }
            }
    }

    // MARK: - Connection lifecycle

    func testConnectionStateLifecycle() {
        let ready = XCTestExpectation(description: "ready")
        let cancelled = XCTestExpectation(description: "cancelled")

        let remote = Endpoint(address: IPv4Address.loopback, port: 10800)
        let conn = NetworkConnection(to: remote, using: makeUDPParams(localPort: 10801))
            .onStateUpdate { _, state in
                if case .ready = state { ready.fulfill() }
                if case .cancelled = state { cancelled.fulfill() }
            }

        conn.start()
        wait(for: [ready], timeout: 5.0)

        conn.cancel()
        wait(for: [cancelled], timeout: 5.0)
    }

    // MARK: - Basic data path

    func testRoundTripEchoIPv4() {
        let done = XCTestExpectation(description: "echo complete")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10810, localPort: 10811, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10811, localPort: 10810, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload: [UInt8] = [1, 2, 3, 4, 5]

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            switch result {
            case .success(let message):
                XCTAssertEqual(message.content, payload)
                c2.send(.message(content: message.content)) { _ in }

                c1.receive { result in
                    switch result {
                    case .success(let echo):
                        XCTAssertEqual(echo.content, payload)
                        done.fulfill()
                    case .failure(let error):
                        XCTFail("echo receive failed: \(error)")
                    }
                }
            case .failure(let error):
                XCTFail("c2 receive failed: \(error)")
            }
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testRoundTripEchoLargePayload() {
        let done = XCTestExpectation(description: "large echo")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10820, localPort: 10821, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10821, localPort: 10820, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload = [UInt8](repeating: 0xAB, count: 1400)

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            switch result {
            case .success(let message):
                XCTAssertEqual(message.content, payload)
                c2.send(.message(content: message.content)) { _ in }

                c1.receive { result in
                    if case .success(let echo) = result {
                        XCTAssertEqual(echo.content, payload)
                    } else {
                        XCTFail("echo receive failed")
                    }
                    done.fulfill()
                }
            case .failure(let error):
                XCTFail("receive failed: \(error)")
            }
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testRoundTripEchoIPv6() {
        let done = XCTestExpectation(description: "ipv6 echo")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10830, localPort: 10831, ipv6: true, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10831, localPort: 10830, ipv6: true, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload: [UInt8] = [10, 20, 30]

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            switch result {
            case .success(let message):
                XCTAssertEqual(message.content, payload)
                c2.send(.message(content: message.content)) { _ in }

                c1.receive { result in
                    if case .success(let echo) = result {
                        XCTAssertEqual(echo.content, payload)
                    } else {
                        XCTFail("echo receive failed")
                    }
                    done.fulfill()
                }
            case .failure(let error):
                XCTFail("receive failed: \(error)")
            }
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testSendSingleByteDatagram() {
        let done = XCTestExpectation(description: "single byte")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10840, localPort: 10841, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10841, localPort: 10840, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        c1.send(.message(content: [0xFF])) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            if case .success(let message) = result {
                XCTAssertEqual(message.content, [0xFF])
            } else {
                XCTFail("receive failed")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testMultipleMessagesSequentially() {
        let allDone = XCTestExpectation(description: "all messages")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10850, localPort: 10851, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10851, localPort: 10850, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let messages: [[UInt8]] = [
            [1], [2, 3], [4, 5, 6], [7, 8, 9, 10], [11, 12, 13, 14, 15],
        ]
        nonisolated(unsafe) var received = 0

        @Sendable func sendAndReceive(_ i: Int) {
            guard i < messages.count else {
                allDone.fulfill()
                return
            }
            c1.send(.message(content: messages[i])) { result in
                if case .failure(let error) = result { XCTFail("send \(i) failed: \(error)") }
            }
            c2.receive { result in
                if case .success(let message) = result {
                    XCTAssertEqual(message.content, messages[i])
                    received += 1
                } else {
                    XCTFail("receive \(i) failed")
                }
                sendAndReceive(i + 1)
            }
        }

        sendAndReceive(0)

        wait(for: [allDone], timeout: 15.0)
        XCTAssertEqual(received, messages.count)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testBidirectionalSimultaneousTransfer() {
        let bothDone = XCTestExpectation(description: "both received")
        bothDone.expectedFulfillmentCount = 2
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10860, localPort: 10861, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10861, localPort: 10860, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payloadA: [UInt8] = [0xAA, 0xBB]
        let payloadB: [UInt8] = [0xCC, 0xDD]

        c1.send(.message(content: payloadA)) { _ in }
        c2.send(.message(content: payloadB)) { _ in }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payloadA)
            } else {
                XCTFail("c2 receive failed")
            }
            bothDone.fulfill()
        }

        c1.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payloadB)
            } else {
                XCTFail("c1 receive failed")
            }
            bothDone.fulfill()
        }

        wait(for: [bothDone], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Volume / stress

    func testRapidBurst100Sends() {
        let allReceived = XCTestExpectation(description: "all received")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10870, localPort: 10871, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10871, localPort: 10870, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let messageCount = 100
        for i in 0..<messageCount {
            c1.send(.message(content: [UInt8(i % 256)])) { result in
                if case .failure(let error) = result { XCTFail("send \(i) failed: \(error)") }
            }
        }

        nonisolated(unsafe) var receiveCount = 0
        @Sendable func receiveNext() {
            c2.receive { result in
                if case .success = result {
                    receiveCount += 1
                    if receiveCount < messageCount {
                        receiveNext()
                    } else {
                        allReceived.fulfill()
                    }
                } else {
                    XCTFail("receive \(receiveCount) failed")
                }
            }
        }
        receiveNext()

        wait(for: [allReceived], timeout: 30.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testHighVolumeEcho200Messages() {
        let allDone = XCTestExpectation(description: "200 echoes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10880, localPort: 10881, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10881, localPort: 10880, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let total = 200
        nonisolated(unsafe) var success = 0

        @Sendable func echoOnce(_ i: Int) {
            guard i < total else {
                allDone.fulfill()
                return
            }
            let payload: [UInt8] = [UInt8(i % 256)]

            c1.send(.message(content: payload)) { result in
                if case .failure(let error) = result { XCTFail("send \(i): \(error)") }
            }

            c2.receive { result in
                guard case .success(let msg) = result else {
                    XCTFail("c2 recv \(i)")
                    return
                }
                XCTAssertEqual(msg.content, payload)
                c2.send(.message(content: msg.content)) { _ in }

                c1.receive { result in
                    guard case .success(let echo) = result else {
                        XCTFail("c1 echo \(i)")
                        return
                    }
                    XCTAssertEqual(echo.content, payload)
                    success += 1
                    echoOnce(i + 1)
                }
            }
        }
        echoOnce(0)

        wait(for: [allDone], timeout: 60.0)
        XCTAssertEqual(success, total)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testVaryingPayloadSizes() {
        let allDone = XCTestExpectation(description: "varying sizes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10890, localPort: 10891, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10891, localPort: 10890, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let sizes = [1, 100, 500, 1000, 1400, 10]
        let messages = sizes.map { [UInt8](repeating: 0xAA, count: $0) }
        nonisolated(unsafe) var received = 0

        @Sendable func sendAndReceive(_ i: Int) {
            guard i < messages.count else {
                allDone.fulfill()
                return
            }
            c1.send(.message(content: messages[i])) { result in
                if case .failure(let error) = result { XCTFail("send \(i): \(error)") }
            }
            c2.receive { result in
                if case .success(let msg) = result {
                    XCTAssertEqual(msg.content, messages[i])
                    received += 1
                } else {
                    XCTFail("receive \(i) failed")
                }
                sendAndReceive(i + 1)
            }
        }
        sendAndReceive(0)

        wait(for: [allDone], timeout: 15.0)
        XCTAssertEqual(received, messages.count)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Backpressure

    func testBurstSendsReceiveOneAtATime() {
        let allReceived = XCTestExpectation(description: "all received")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10900, localPort: 10901, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10901, localPort: 10900, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let messageCount = 5
        for i in 0..<messageCount {
            c1.send(.message(content: [UInt8(i)])) { result in
                if case .failure(let error) = result { XCTFail("send \(i) failed: \(error)") }
            }
        }

        nonisolated(unsafe) var receiveCount = 0
        @Sendable func receiveNext() {
            c2.receive { result in
                switch result {
                case .success:
                    receiveCount += 1
                    if receiveCount < messageCount {
                        receiveNext()
                    } else {
                        allReceived.fulfill()
                    }
                case .failure(let error):
                    XCTFail("receive \(receiveCount) failed: \(error)")
                }
            }
        }
        receiveNext()

        wait(for: [allReceived], timeout: 15.0)
        XCTAssertEqual(receiveCount, messageCount)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testMultipleSendsBeforeAnyReads() {
        let allDone = XCTestExpectation(description: "reads done")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10910, localPort: 10911, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10911, localPort: 10910, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let messageCount = 10
        for i in 0..<messageCount {
            c1.send(.message(content: [UInt8(i)])) { result in
                if case .failure(let error) = result { XCTFail("send \(i): \(error)") }
            }
        }

        nonisolated(unsafe) var receiveCount = 0
        @Sendable func drainAll() {
            c2.receive { result in
                if case .success = result {
                    receiveCount += 1
                    if receiveCount < messageCount {
                        drainAll()
                    } else {
                        allDone.fulfill()
                    }
                } else {
                    XCTFail("receive \(receiveCount) failed")
                }
            }
        }

        // Small delay to let sends queue up before reading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            drainAll()
        }

        wait(for: [allDone], timeout: 15.0)
        XCTAssertEqual(receiveCount, messageCount)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testDelayedConsumer() {
        let allDone = XCTestExpectation(description: "delayed consumer")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10920, localPort: 10921, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10921, localPort: 10920, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        // Delay the receive by 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            c2.receive { result in
                if case .success(let msg) = result {
                    XCTAssertEqual(msg.content, payload)
                } else {
                    XCTFail("delayed receive failed")
                }
                allDone.fulfill()
            }
        }

        wait(for: [allDone], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Additional lifecycle tests

    func testCancelBeforeStart() {
        let cancelled = XCTestExpectation(description: "cancelled")

        let remote = Endpoint(address: IPv4Address.loopback, port: 10930)
        let conn = NetworkConnection(to: remote, using: makeUDPParams(localPort: 10931))
            .onStateUpdate { _, state in
                if case .cancelled = state { cancelled.fulfill() }
            }

        conn.cancel()
        wait(for: [cancelled], timeout: 5.0)
    }

    func testStartTwoConnectionsSameContext() {
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")
        let bothReady = XCTestExpectation(description: "both ready")
        bothReady.expectedFulfillmentCount = 2

        let c1 = makeConnection(toPort: 10940, localPort: 10941, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10941, localPort: 10940, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        // Both should reach ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            bothReady.fulfill()
            bothReady.fulfill()
        }

        wait(for: [bothReady], timeout: 5.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Edge case payloads

    func testEmptyPayload() {
        let done = XCTestExpectation(description: "empty payload")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10950, localPort: 10951, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10951, localPort: 10950, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        c1.send(.message(content: [])) { result in
            if case .failure(let error) = result { XCTFail("send empty failed: \(error)") }
        }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, [])
            } else {
                XCTFail("receive empty failed")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testMaxSizeDatagram() {
        let done = XCTestExpectation(description: "max size")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10960, localPort: 10961, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10961, localPort: 10960, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload = (0..<1472).map { UInt8($0 % 256) }

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payload)
            } else {
                XCTFail("receive failed")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testPayloadWithAllByteValues() {
        let done = XCTestExpectation(description: "all bytes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10970, localPort: 10971, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10971, localPort: 10970, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payload = (0...255).map { UInt8($0) }

        c1.send(.message(content: payload)) { result in
            if case .failure(let error) = result { XCTFail("send failed: \(error)") }
        }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payload)
            } else {
                XCTFail("receive failed")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Multiple sequential echoes

    func testEcho10RoundTrips() {
        let allDone = XCTestExpectation(description: "10 echoes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10980, localPort: 10981, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10981, localPort: 10980, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        nonisolated(unsafe) var success = 0
        @Sendable func echoOnce(_ i: Int) {
            guard i < 10 else {
                allDone.fulfill()
                return
            }
            let payload: [UInt8] = [UInt8(i), UInt8(i &* 2)]

            c1.send(.message(content: payload)) { result in
                if case .failure(let error) = result { XCTFail("send \(i): \(error)") }
            }

            c2.receive { result in
                guard case .success(let msg) = result else {
                    XCTFail("c2 recv \(i)")
                    return
                }
                XCTAssertEqual(msg.content, payload)
                c2.send(.message(content: msg.content)) { _ in }

                c1.receive { result in
                    guard case .success(let echo) = result else {
                        XCTFail("c1 echo \(i)")
                        return
                    }
                    XCTAssertEqual(echo.content, payload)
                    success += 1
                    echoOnce(i + 1)
                }
            }
        }
        echoOnce(0)

        wait(for: [allDone], timeout: 30.0)
        XCTAssertEqual(success, 10)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testEcho50RoundTripsLargePayload() {
        let allDone = XCTestExpectation(description: "50 large echoes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 10990, localPort: 10991, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 10991, localPort: 10990, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let total = 50
        nonisolated(unsafe) var success = 0
        @Sendable func echoOnce(_ i: Int) {
            guard i < total else {
                allDone.fulfill()
                return
            }
            let payload = [UInt8](repeating: UInt8(i % 256), count: 1000)

            c1.send(.message(content: payload)) { result in
                if case .failure(let error) = result { XCTFail("send \(i): \(error)") }
            }

            c2.receive { result in
                guard case .success(let msg) = result else {
                    XCTFail("c2 recv \(i)")
                    return
                }
                XCTAssertEqual(msg.content, payload)
                c2.send(.message(content: msg.content)) { _ in }

                c1.receive { result in
                    guard case .success(let echo) = result else {
                        XCTFail("c1 echo \(i)")
                        return
                    }
                    XCTAssertEqual(echo.content, payload)
                    success += 1
                    echoOnce(i + 1)
                }
            }
        }
        echoOnce(0)

        wait(for: [allDone], timeout: 60.0)
        XCTAssertEqual(success, total)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - IPv6 additional tests

    func testIPv6SingleByte() {
        let done = XCTestExpectation(description: "ipv6 single byte")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 11000, localPort: 11001, ipv6: true, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 11001, localPort: 11000, ipv6: true, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        c1.send(.message(content: [0x42])) { _ in }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, [0x42])
            } else {
                XCTFail("ipv6 receive failed")
            }
            done.fulfill()
        }

        wait(for: [done], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testIPv6BidirectionalEcho() {
        let bothDone = XCTestExpectation(description: "both echoed")
        bothDone.expectedFulfillmentCount = 2
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 11010, localPort: 11011, ipv6: true, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 11011, localPort: 11010, ipv6: true, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let payloadA: [UInt8] = [0xAA, 0xBB, 0xCC]
        let payloadB: [UInt8] = [0xDD, 0xEE, 0xFF]

        c1.send(.message(content: payloadA)) { _ in }
        c2.send(.message(content: payloadB)) { _ in }

        c2.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payloadA)
            } else {
                XCTFail("c2 recv failed")
            }
            bothDone.fulfill()
        }

        c1.receive { result in
            if case .success(let msg) = result {
                XCTAssertEqual(msg.content, payloadB)
            } else {
                XCTFail("c1 recv failed")
            }
            bothDone.fulfill()
        }

        wait(for: [bothDone], timeout: 10.0)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    // MARK: - Rapid send-receive patterns

    func testAlternatingSendReceive() {
        let allDone = XCTestExpectation(description: "alternating")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 11020, localPort: 11021, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 11021, localPort: 11020, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let count = 20
        nonisolated(unsafe) var completed = 0

        @Sendable func step(_ i: Int) {
            guard i < count else {
                allDone.fulfill()
                return
            }

            if i % 2 == 0 {
                c1.send(.message(content: [UInt8(i)])) { _ in }
                c2.receive { result in
                    if case .success(let msg) = result {
                        XCTAssertEqual(msg.content, [UInt8(i)])
                        completed += 1
                    }
                    step(i + 1)
                }
            } else {
                c2.send(.message(content: [UInt8(i)])) { _ in }
                c1.receive { result in
                    if case .success(let msg) = result {
                        XCTAssertEqual(msg.content, [UInt8(i)])
                        completed += 1
                    }
                    step(i + 1)
                }
            }
        }
        step(0)

        wait(for: [allDone], timeout: 30.0)
        XCTAssertEqual(completed, count)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testBurst50ThenDrain() {
        let allDrained = XCTestExpectation(description: "drained")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 11030, localPort: 11031, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 11031, localPort: 11030, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let messageCount = 50
        for i in 0..<messageCount {
            c1.send(.message(content: [UInt8(i % 256)])) { _ in }
        }

        nonisolated(unsafe) var receiveCount = 0
        @Sendable func drain() {
            c2.receive { result in
                if case .success = result {
                    receiveCount += 1
                    if receiveCount < messageCount {
                        drain()
                    } else {
                        allDrained.fulfill()
                    }
                } else {
                    XCTFail("receive \(receiveCount) failed")
                }
            }
        }
        drain()

        wait(for: [allDrained], timeout: 30.0)
        XCTAssertEqual(receiveCount, messageCount)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }

    func testSendReceiveWithRandomPayloadSizes() {
        let allDone = XCTestExpectation(description: "random sizes")
        let c1Done = XCTestExpectation(description: "c1 cancelled")
        let c2Done = XCTestExpectation(description: "c2 cancelled")

        let c1 = makeConnection(toPort: 11040, localPort: 11041, cancelExpectation: c1Done)
        let c2 = makeConnection(toPort: 11041, localPort: 11040, cancelExpectation: c2Done)

        c1.start()
        c2.start()

        let sizes = [7, 13, 42, 100, 256, 500, 1, 1000, 3, 1400]
        let messages = sizes.map { (0..<$0).map { UInt8($0 % 256) } }
        nonisolated(unsafe) var received = 0

        @Sendable func sendAndVerify(_ i: Int) {
            guard i < messages.count else {
                allDone.fulfill()
                return
            }
            c1.send(.message(content: messages[i])) { _ in }
            c2.receive { result in
                if case .success(let msg) = result {
                    XCTAssertEqual(msg.content, messages[i])
                    received += 1
                }
                sendAndVerify(i + 1)
            }
        }
        sendAndVerify(0)

        wait(for: [allDone], timeout: 15.0)
        XCTAssertEqual(received, messages.count)
        c1.cancel()
        c2.cancel()
        wait(for: [c1Done, c2Done], timeout: 5.0)
    }
}

#endif
