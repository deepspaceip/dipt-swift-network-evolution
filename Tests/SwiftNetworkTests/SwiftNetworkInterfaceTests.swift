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
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

@available(Network 0.1.0, *)
final class SwiftNetworkInterfaceTests: NetTestCase {

    // Create interface with bad index, Darwin will abort on index 0 so this is guarded
    func testCreateInterfaceByBadIndex() throws {
        XCTAssertThrowsError(try Interface(index: 0))
    }

    func testCreateInterfaceByValidIndex() throws {
        var name = "lo0"
        var mtu = 16384
        #if os(Linux)
        name = "lo"
        mtu = 65536
        #endif
        // Use 1 as the index as this should be lo on even a machine that is not connected to the internet
        let interface = try Interface(index: 1)
        XCTAssertNotNil(interface, "Interface of index 1 should be valid")
        XCTAssertEqual(interface.name, name, "Name should be valid")
        XCTAssertEqual(interface.index, 1, "Index should be equal to 1")
        XCTAssertEqual(interface.details.mtu, mtu, "lo should have a max MTU")
        XCTAssertEqual(interface.interfaceType, .loopback, "Interface should be of loopback type")
    }

    func testCreateInterfaceByValidIndexAndName() throws {
        var name = "lo0"
        #if os(Linux)
        name = "lo"
        #endif
        let interface = try Interface(index: 1, name: name)
        XCTAssertEqual(interface.name, name, "Name should be valid")
        XCTAssertEqual(interface.index, 1, "Index should be equal to 1")
        XCTAssertEqual(interface.interfaceType, .loopback, "Interface should be of loopback type")
        #if canImport(Darwin)
        XCTAssertTrue(interface.details.flags.contains(.supportsMulticast), "supportsMulticast flag should be present")
        #endif
    }

    func testCreateInterfaceWithTooManySockets() throws {
        // Create enough sockets to hit the fd limit so that we can't make the ioctl socket in the interface
        var sockets: [Int32] = []
        let fdLimit = System.getFDLimit()
        let systemFDLimit = try XCTUnwrap(fdLimit)
        var socketsExhausted = false
        for _ in 0..<systemFDLimit {
            #if !os(Linux)
            let wastedSockFd = socket(AF_INET, SOCK_DGRAM, 0)
            #else  //os(Linux)
            let wastedSockFd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
            #endif
            if wastedSockFd < 0 {
                Logger.proto.info("successfully opened too many sockets")
                socketsExhausted = true
                break
            }
            sockets.append(wastedSockFd)
        }
        XCTAssertTrue(socketsExhausted, "Sockets were not exhausted")
        #if !os(Linux)
        let name = "lo0"
        #else  //os(Linux)
        let name = "lo"
        #endif
        // This should throw here if the file descriptor limit is reached
        // Note that in the internal build path this will just return nil for someone tring to create an Interface.
        // This is similar to how it previously used to work, but input or an issue, return nil
        XCTAssertThrowsError(try Interface(index: 1, name: name))
        // Clean up the sockets
        for sockFd in sockets {
            close(sockFd)
        }
    }

    func testCompareTwoInterfaces() throws {
        var name = "lo0"
        #if os(Linux)
        name = "lo"
        #endif
        let interfaceByIndex = try Interface(index: 1)
        let interfaceWithName = try Interface(index: 1, name: name)

        XCTAssertEqual(interfaceByIndex, interfaceWithName)

        XCTAssertEqual(interfaceByIndex.name, name, "Name should be \(name)")
        XCTAssertEqual(interfaceByIndex.name, interfaceWithName.name, "Names should be equal")

        XCTAssertEqual(interfaceByIndex.index, 1, "Index should be 1")
        XCTAssertEqual(interfaceByIndex.index, interfaceWithName.index, "Indices should be equal")

        XCTAssertEqual(interfaceByIndex.interfaceType, .loopback, "Type should be loopback")
        XCTAssertEqual(interfaceByIndex.interfaceType, interfaceWithName.interfaceType, "Types should match")

        XCTAssertEqual(
            interfaceByIndex.details.flags.rawValue,
            interfaceWithName.details.flags.rawValue,
            "Flags should match"
        )
    }

    func testRouteGetInterfaceIndex() {
        // Very basic localhost test
        let v4Bytes: [UInt8] = [0x7F, 0x00, 0x00, 0x01]

        let address = IPv4Address(v4Bytes)
        XCTAssertNotNil(address)
        let routeIndex1 = try! System.routeGetInterfaceIndex(dst: address!, scopedIndex: 0)

        // Add the Darwin check for now until Linux support is added
        #if canImport(Darwin)
        XCTAssertEqual(routeIndex1, 1)
        #elseif os(Linux)
        XCTAssert(routeIndex1 > 0)
        #endif
        var ipv4Addr2 = sockaddr_in()
        let _ = "10.0.0.1".withCString { p in
            inet_pton(Int32(AddressFamily.ipv4.rawValue), p, &ipv4Addr2.sin_addr)
        }

        let address2 = IPv4Address(ipv4Addr2.sin_addr.s_addr)
        XCTAssertNotNil(address2)
        let routeIndex2 = try! System.routeGetInterfaceIndex(dst: address2, scopedIndex: 0)

        XCTAssert(routeIndex2 > 0)

        let ipv6Address = IPv6Address([
            0xfd, 0x5a, 0x3a, 0x11, 0xd8, 0x84, 0x73, 0x40, 0x08, 0xa7, 0x8a, 0xda, 0x1c, 0x36, 0x68, 0x64,
        ])!
        let routeIndex3 = try! System.routeGetInterfaceIndex(dst: ipv6Address, scopedIndex: 1)
        XCTAssertEqual(routeIndex3, 1)

        // Use a v6 loopback address with a scoped interface index
        let routeIndex4 = try! System.routeGetInterfaceIndex(dst: IPv6Address.loopback, scopedIndex: 1)
        XCTAssertEqual(routeIndex4, 1)
    }
}
