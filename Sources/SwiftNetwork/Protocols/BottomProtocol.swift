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

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

// MARK: - Bottom Protocol Adoption

/// Bottom protocols sit at the bottom of a stack and have only an upper protocol.
///
/// Conform to `BottomStreamProtocol` or `BottomDatagramProtocol`.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomProtocolHandler: ~Copyable, OutboundDataHandler {

    /// The type of upper protocol (toward the app) that you can attach.
    var upper: UpperProtocol { get set }

    /// Sets up a protocol instance with parameters and endpoints.
    ///
    /// Protocols can implement this function to customize behavior.
    func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    /// Tears down a protocol when detaching.
    ///
    /// Protocols can implement this function to customize behavior.
    func teardown()

    /// Requests that this protocol initiate its handshake, if any.
    ///
    /// If not implemented, the protocol delivers the connected event automatically.
    /// Protocols can implement this function to customize behavior.
    func connect()

    /// Requests that this protocol gracefully close.
    ///
    /// Protocols can implement this function to customize behavior.
    func disconnect()

    /// Handles an event the app sent.
    ///
    /// Protocols can implement this function to customize behavior.
    func handleApplicationEvent(_ event: ApplicationEvent)

    #if !NETWORK_EMBEDDED
    /// The metadata state for this protocol.
    var metadata: AbstractProtocolMetadata? { get }
    #endif
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable {
    /// Indicates to the upper protocol that this protocol is connected.
    ///
    /// Call this only if the protocol customizes `connect()`.
    public func deliverConnectedEvent() {
        fromExternal {
            upper.deliverConnectedEvent(self.reference)
        }
    }

    /// Indicates to the upper protocol that this protocol is disconnected, with an error.
    public func deliverDisconnectedEvent(error: NetworkError?) {
        fromExternal {
            upper.deliverDisconnectedEvent(self.reference, error: error)
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension BottomProtocolHandler where Self: ~Copyable, UpperProtocol: InboundDataLinkage {
    /// Indicates to the upper protocol that this protocol has data available to read.
    public func deliverInboundDataAvailableEvent() {
        fromExternal {
            guard isConnected else { return }
            upper.deliverInboundDataAvailableEvent(self.reference)
        }
    }

    /// Indicates to the upper protocol that this protocol has room available to send.
    public func deliverOutboundRoomAvailableEvent() {
        fromExternal {
            guard isConnected else { return }
            upper.deliverOutboundRoomAvailableEvent(self.reference)
        }
    }

    /// Passes an event to the upper protocol.
    public func deliverNetworkProtocolEvent(_ event: NetworkProtocolEvent) {
        fromExternal {
            upper.deliverNetworkProtocolEvent(
                originalReference: self.reference,
                selfReference: self.reference,
                event: event
            )
        }
    }
}

/// Bottom protocol with an upper stream linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomStreamProtocol: ~Copyable, BottomProtocolHandler, OutboundStreamHandler
where UpperProtocol == InboundStreamLinkage {

    /// Returns received stream data to the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray?

    /// Returns the number of bytes of stream data that can be written.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int

    /// Sends stream data created by the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError)
}

/// Bottom protocol with an upper datagram linkage.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol BottomDatagramProtocol: ~Copyable, BottomProtocolHandler, OutboundDatagramHandler
where UpperProtocol == InboundDatagramLinkage {

    /// Returns received datagrams to the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func receiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray?

    /// Returns datagram frames the upper protocol can use to send.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func getDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    /// Sends datagrams created by the upper protocol.
    ///
    /// Protocols can implement this function to customize behavior.
    mutating func sendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError)
}

// MARK: - Bottom Protocol Implementation Details

extension BottomProtocolHandler where Self: ~Copyable {
    var asLower: UpperProtocol.PairedLinkage { .init(reference: reference) }

    public func handleApplicationEvent(_ from: ProtocolInstanceReference, event: ApplicationEvent) {
        // Don't validate upper, can pass through
        self.handleApplicationEvent(event)
    }

    internal func validate(
        upper upperProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard upperProtocol == upper.reference else {
            Logger.proto.fault("Received \'\(label)\' from incorrect upper protocol")
            throw ProtocolInstanceError.invalidUpperProtocol
        }
        #endif
    }

    #if !NETWORK_EMBEDDED
    public mutating func attachUpperProtocol<Linkage: LowerProtocolLinkage>(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> Linkage {
        guard Linkage.self == UpperProtocol.PairedLinkage.self else {
            throw NetworkError.posix(ENOTSUP)
        }
        guard upper.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        upper = UpperProtocol(reference: from)

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init(reference: .init())
            throw error
        }

        return asLower as! Linkage
    }
    #endif

    public mutating func detach(_ from: ProtocolInstanceReference) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        upper = .init(reference: .init())
        teardown()
    }

    public func connect(_ from: ProtocolInstanceReference) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallConnect(requested: true) {
            connect()
        }
    }

    public func disconnect(_ from: ProtocolInstanceReference, error: NetworkError?) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallDisconnect {
            disconnect()
        }
    }

    public func getMetadata<P: NetworkProtocol>(_ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
        do { try validate(upper: from, #function) } catch { return nil }
        #if !NETWORK_EMBEDDED
        if let metadata = self.metadata as? ProtocolMetadata<P> {
            return metadata
        }
        #endif
        return nil
    }

    #if !NETWORK_EMBEDDED
    public func getOptions<T>(from parameters: Parameters) -> ProtocolOptions<T>? {
        parameters.protocolOptions(for: self.reference)
    }
    public func getOptions(from parameters: Parameters) -> AbstractProtocolOptions? {
        parameters.protocolOptions(for: self.reference)
    }
    #endif
}

// Default implementations, to be overridden as necessary
extension BottomProtocolHandler where Self: ~Copyable {
    public func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {}

    public func teardown() {}

    public func connect() {
        deliverConnectedEvent()
    }

    public func disconnect() {
        deliverDisconnectedEvent(error: nil)
    }

    public func handleApplicationEvent(_ event: ApplicationEvent) {}

    #if !NETWORK_EMBEDDED
    public var metadata: AbstractProtocolMetadata? { nil }
    #endif
}

extension BottomProtocolHandler where Self: ~Copyable, UpperProtocol == InboundDatagramLinkage {
    public mutating func attachUpperDatagramProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundDatagramLinkage {
        guard upper.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        upper = UpperProtocol(reference: from)

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init(reference: .init())
            throw error
        }

        return asLower
    }
}

extension BottomProtocolHandler where Self: ~Copyable, UpperProtocol == InboundStreamLinkage {
    public mutating func attachUpperStreamProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundStreamLinkage {
        guard upper.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        upper = UpperProtocol(reference: from)

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init(reference: .init())
            throw error
        }

        return asLower
    }
}

extension BottomDatagramProtocol where Self: ~Copyable {
    public mutating func receiveDatagrams(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveDatagrams(maximumDatagramCount: maximumDatagramCount)
    }
    public mutating func getDatagramsToSend(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.getDatagramsToSend(
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }
    public mutating func sendDatagrams(
        _ from: ProtocolInstanceReference,
        datagrams: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected else {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendDatagrams(datagrams)
    }
}

extension BottomStreamProtocol where Self: ~Copyable {
    public mutating func receiveStreamData(
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveStreamData(minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }
    public mutating func getOutboundStreamDataRoomAvailable(
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.getOutboundStreamDataRoomAvailable()
    }
    public mutating func sendStreamData(
        _ from: ProtocolInstanceReference,
        streamData: consuming FrameArray
    ) throws(NetworkError) {
        do { try validate(upper: from, #function) } catch {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(EINVAL)
        }
        guard isConnected else {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendStreamData(streamData)
    }
}
