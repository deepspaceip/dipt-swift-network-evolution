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

#if (NETWORK_EMBEDDED || NETWORK_STANDALONE) && !NETWORK_DRIVERKIT

/// Set of Embedded system APIs for interacting with the system interface
internal enum SystemInterface {

    /// Get MTU from the intereface using ioctl
    static func interfaceGetMTU(socket: Int32, name: String) throws -> Int {
        1500
    }

    /// Check to see if an interface has a specific flag.  For exampe, UP,RUNNING,BROADFAST,MULTICAST
    static func interfaceHasFlag(socket: Int32, name: String, flag: Interface.Details.Flags) throws -> Bool {
        false
    }

    /// Get functional type flags for the interface
    static func getFunctionalType(socket: Int32, name: String) throws -> UInt32 {
        0
    }

    /// Get all of the interface flags for a specified interface
    static func interfaceGetInterfaceFlags(socket: Int32, name: String) throws -> UInt32 {
        0
    }

    /// Get all of the interface type for a specified interface
    static func interfaceGetInterfaceType(socket: Int32, name: String) throws -> InterfaceType {
        .loopback
    }

    /// Get interface sub type
    static func interfaceGetInterfaceSubType(socket: Int32, name: String) throws -> InterfaceSubtype {
        .wifiInfrastructure
    }

    /// Get interface name from index
    static func interfaceGetNameFromIndex(index: UInt32) throws -> String? {
        String("BogusInterface")
    }
}

internal enum SystemRoute {
    static func routeGetInterfaceIndex(dst: any IPAddress, scopedIndex: UInt32 = 0) throws -> UInt32 {
        // No route lookups on embedded
        0
    }
}
#endif
