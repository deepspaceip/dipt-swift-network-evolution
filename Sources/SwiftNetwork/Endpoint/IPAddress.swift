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

/// IPAddress is just a stub for now.
protocol IPAddress: Sendable {

    /// Create IPAddress from raw bytes
    init?(_ bytes: [UInt8])

    /// Indicates the address family used for the IPAddress type
    var addressFamily: AddressFamily { get }

    /// Indicates if this address is loopback
    var isLoopback: Bool { get }

    /// Indicates if this address is multicast
    var isMulticast: Bool { get }
}
