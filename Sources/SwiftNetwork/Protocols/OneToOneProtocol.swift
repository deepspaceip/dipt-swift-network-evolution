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

// MARK: - One-to-One Protocol Adoption

/// One-to-one protocols are the most basic kinds of protocols that have both
/// an upper and lower protocol. Conform to `OneToOneStreamProtocol`,
/// `OneToOneDatagramProtocol`, or `OneToOneStreamToDatagramProtocol`.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OneToOneProtocolHandler: ~Copyable, OutboundDataHandler, InboundDataHandler, LoggableProtocol {

    /// The type of upper protocol (towards the application) that can be attached
    var upper: UpperProtocol { get set }

    /// The type of lower protocol (towards the network) that can be attached
    var lower: LowerProtocol { get set }

    /// A function called to set up a protocol instance with parameters and endpoints
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)

    /// A function called when detaching a protocol
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func teardown()

    /// A function called to request that this protocol initiate its handshake, if any.
    /// If not implemented, the protocol will deliver the connected event automatically.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func connect()

    /// A function called to request that this protocol gracefully close.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func disconnect(error: NetworkError?)

    /// A function called when the lower protocol has disconnected.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleDisconnectedEvent(error: NetworkError?)

    /// A function called when some lower protocol has sent an event.
    /// Return `.consumed` if the event was handled and should not be passed up to
    /// upper protocols, and `.unconsumed` otherwise.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleNetworkProtocolEvent(_ event: NetworkProtocolEvent) -> HandleNetworkEventResult

    /// A function called when the application has sent an event.
    /// Return `.consumed` if the event was handled and should not be passed down to
    /// lower protocols, and `.unconsumed` otherwise.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleApplicationEvent(_ event: ApplicationEvent) -> HandleNetworkEventResult

    #if !NETWORK_EMBEDDED
    /// Set the metadata state for this protocol
    var metadata: AbstractProtocolMetadata? { get }
    #endif

    /// Return true if this protocol does not directly handle any events, but instead only passes through
    /// NOTE: Protocols that do not want to handle events should set true initially.
    /// The stack may set this to false explicitly, in which case it should not be set back to true.
    var passthroughEvents: Bool { get set }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public enum HandleNetworkEventResult {
    /// The event was handled and consumed by the protocol, and should not be automatically
    /// passed on to the next protocol.
    case consumed

    /// The event was not consumed by the protocol, and is allowed to be automatically
    /// passed on to the next protocol.
    case unconsumed
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension OneToOneProtocolHandler where Self: ~Copyable {
    /// A function to call to indicate to the upper protocol that this protocol is connected.
    /// This is only needed if the protocol customizes `connect()`
    public func deliverConnectedEvent() {
        upper.deliverConnectedEvent(self.reference)
    }

    /// A function to call to indicate to the upper protocol that this protocol is disconnected,
    /// with an error.
    public func deliverDisconnectedEvent(error: NetworkError?) {
        upper.deliverDisconnectedEvent(self.reference, error: error)
    }

    /// A function to call to pass an event to the upper protocol.
    public func deliverNetworkProtocolEvent(_ event: NetworkProtocolEvent) {
        upper.deliverNetworkProtocolEvent(
            originalReference: self.reference,
            selfReference: self.reference,
            event: event
        )
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OneToOneDatapathProtocol: ~Copyable, OneToOneProtocolHandler
where UpperProtocol: InboundDataLinkage, LowerProtocol: OutboundDataLinkage {

    /// A function called when the lower protocol has inbound data available to read.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleInboundDataAvailableEvent()

    /// A function called when the lower protocol has outbound room available to sent.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleOutboundRoomAvailableEvent()
}

/// One-to-one protocol with an upper stream linkage and a lower stream linkage
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OneToOneStreamProtocol: ~Copyable, OneToOneDatapathProtocol
where UpperProtocol == InboundStreamLinkage, LowerProtocol == OutboundStreamLinkage {

    /// A function called when the upper protocol is trying to read stream data.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray?

    /// A function called when the upper protocol is trying to check how much stream data can be written
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int

    /// A function called when the upper protocol is trying to write stream data.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError)

    /// A function called when the lower protocol has reported that the inbound direction of data has been aborted.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleInboundAbortedEvent(error: NetworkError?)

    /// A function called when the lower protocol has reported that the outbound direction of data has been aborted.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func handleOutboundAbortedEvent(error: NetworkError?)
}

/// One-to-one protocol with an upper stream linkage and a lower datagram linkage
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OneToOneStreamToDatagramProtocol: ~Copyable, OneToOneDatapathProtocol
where UpperProtocol == InboundStreamLinkage, LowerProtocol == OutboundDatagramLinkage {

    /// A function called when the upper protocol is trying to read stream data.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func receiveStreamData(minimumBytes: Int, maximumBytes: Int) throws(NetworkError) -> FrameArray?

    /// A function called when the upper protocol is trying to check how much stream data can be written
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func getOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int

    /// A function called when the upper protocol is trying to write stream data.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func sendStreamData(_ streamData: consuming FrameArray) throws(NetworkError)
}

/// One-to-one protocol with an upper datagram linkage and a lower datagram linkage
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OneToOneDatagramProtocol: ~Copyable, OneToOneDatapathProtocol
where UpperProtocol == InboundDatagramLinkage, LowerProtocol == OutboundDatagramLinkage {

    /// A function called when the upper protocol is trying to read datagrams.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func receiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray?

    /// A function called when the upper protocol is trying to get datagram frames to send.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func getDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?

    /// A function called when the upper protocol is trying to send datagrams.
    /// NOTE: Protocols can implement this function to customize behavior
    mutating func sendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError)
}

// MARK: - One-to-One Protocol Implementation Details

extension OneToOneProtocolHandler where Self: ~Copyable {
    var asUpper: LowerProtocol.PairedLinkage { .init(reference: reference) }
    var asLower: UpperProtocol.PairedLinkage { .init(reference: reference) }

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

    internal func validate(
        lower lowerProtocol: ProtocolInstanceReference,
        _ label: String
    ) throws(ProtocolInstanceError) {
        #if DEBUG
        guard !lowerProtocol.isNone else {
            Logger.proto.fault("Received \'\(label)\' from incorrect lower protocol")
            throw ProtocolInstanceError.invalidLowerProtocol
        }
        #endif
    }

    public func invokeConnect() {
        lower.invokeConnect(effectiveSelfReference)
    }

    public func invokeDisconnect(error: NetworkError? = nil) {
        lower.invokeDisconnect(effectiveSelfReference, error: error)
    }

    #if !NETWORK_EMBEDDED
    public mutating func attachLowerProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        if upper.isDetached {
            // If the upper is detached at the time of attaching the lower, don't pass through events
            passthroughEvents = false
        }
        self.lower = try lowerProtocol.attachUpperProtocol(
            reference,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

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

        if let parameters {
            if let options = getOptions(from: parameters) {
                self.log.logPrefix = options.logIDString ?? ""
            }
        }

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
        let reference = effectiveSelfReference
        upper = .init(reference: .init())
        teardown()
        try lower.invokeDetach(reference)
        lower = .init(reference: .init())
    }

    public mutating func connect(_ from: ProtocolInstanceReference) {
        do { try validate(upper: from, #function) } catch { return }
        if lower.isConnected {
            if canCallConnect(requested: true) {
                connect()
            }
        } else {
            connectRequested()
            invokeConnect()
        }
    }

    public mutating func disconnect(_ from: ProtocolInstanceReference, error: NetworkError?) {
        do { try validate(upper: from, #function) } catch { return }
        if canCallDisconnect {
            disconnect(error: error)
        }
    }

    public mutating func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        do { try validate(lower: from, #function) } catch { return }
        if canCallConnect(requested: false) {
            connect()
        }
    }

    public mutating func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleDisconnectedEvent(error: error)
    }

    public mutating func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent) {
        // Don't validate lower, can pass through
        if self.handleNetworkProtocolEvent(event) == .consumed { return }
        upper.deliverNetworkProtocolEvent(originalReference: from, selfReference: self.reference, event: event)
    }

    public mutating func handleApplicationEvent(_ from: ProtocolInstanceReference, event: ApplicationEvent) {
        // Don't validate upper, can pass through
        if self.handleApplicationEvent(event) == .consumed { return }
        lower.invokeApplicationEvent(from, event: event)
    }

    public func getMetadata<P: NetworkProtocol>(_ from: ProtocolInstanceReference) -> ProtocolMetadata<P>? {
        do { try validate(upper: from, #function) } catch { return nil }
        #if !NETWORK_EMBEDDED
        if let metadata = self.metadata as? ProtocolMetadata<P> {
            return metadata
        }
        return lower.invokeGetMetadata(effectiveSelfReference)
        #else
        return nil
        #endif
    }

    public func tlsOptions(from parameters: Parameters) -> ProtocolOptions<SwiftTLSProtocol>? {
        parameters.tlsOptions(for: self.reference)
    }
    public func udpOptions(from parameters: Parameters) -> ProtocolOptions<UDPProtocol>? {
        parameters.udpOptions(for: self.reference)
    }
    public func ipOptions(from parameters: Parameters) -> ProtocolOptions<IPProtocol>? {
        parameters.ipOptions(for: self.reference)
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
extension OneToOneProtocolHandler where Self: ~Copyable {
    public mutating func setup(
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {}

    public mutating func teardown() {}

    public mutating func connect() {
        deliverConnectedEvent()
    }

    public mutating func disconnect(error: NetworkError?) {
        invokeDisconnect(error: error)
    }

    public mutating func handleDisconnectedEvent(error: NetworkError?) {
        deliverDisconnectedEvent(error: error)
    }

    public mutating func handleNetworkProtocolEvent(_ event: NetworkProtocolEvent) -> HandleNetworkEventResult {
        .unconsumed
    }

    public mutating func handleApplicationEvent(_ event: ApplicationEvent) -> HandleNetworkEventResult {
        .unconsumed
    }
}

extension OneToOneProtocolHandler where Self: ~Copyable {
    @inline(__always)
    var effectiveSelfReference: ProtocolInstanceReference {
        if passthroughEvents {
            return upper.reference
        } else {
            return self.reference
        }
    }
}

extension OneToOneDatapathProtocol where Self: ~Copyable {
    public mutating func handleInboundDataAvailableEvent(_ from: ProtocolInstanceReference) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleInboundDataAvailableEvent()
    }

    public mutating func handleOutboundRoomAvailableEvent(_ from: ProtocolInstanceReference) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleOutboundRoomAvailableEvent()
    }

    public func deliverInboundDataAvailableEvent() {
        guard passthroughEvents || isConnected else { return }
        upper.deliverInboundDataAvailableEvent(self.reference)
    }

    public func deliverOutboundRoomAvailableEvent() {
        guard passthroughEvents || isConnected else { return }
        upper.deliverOutboundRoomAvailableEvent(self.reference)
    }
}

extension OneToOneDatapathProtocol where Self: ~Copyable {
    // Default implementations, to be overridden as necessary
    public mutating func handleInboundDataAvailableEvent() {
        deliverInboundDataAvailableEvent()
    }

    public mutating func handleOutboundRoomAvailableEvent() {
        deliverOutboundRoomAvailableEvent()
    }
}

extension OneToOneProtocolHandler where Self: ~Copyable, UpperProtocol == InboundDatagramLinkage {
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

        #if !NETWORK_EMBEDDED
        if let parameters {
            if let options = getOptions(from: parameters) {
                self.log.logPrefix = options.logIDString ?? ""
            }
        }
        #endif

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init(reference: .init())
            throw error
        }

        return asLower
    }

    public func deliverInboundDataAvailableEvent() {
        guard passthroughEvents || isConnected else { return }
        upper.deliverInboundDataAvailableEvent(self.reference)
    }
}

extension OneToOneProtocolHandler where Self: ~Copyable, UpperProtocol == InboundStreamLinkage {
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

        #if !NETWORK_EMBEDDED
        if let parameters {
            if let options = getOptions(from: parameters) {
                self.log.logPrefix = options.logIDString ?? ""
            }
        }
        #endif

        do {
            try self.setup(remote: remote, local: local, parameters: parameters, path: path)
        } catch let error {
            upper = .init(reference: .init())
            throw error
        }

        return asLower
    }
}

extension OneToOneProtocolHandler where Self: ~Copyable, LowerProtocol == OutboundDatagramLinkage {
    public mutating func attachLowerDatagramProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        if upper.isDetached {
            // If the upper is detached at the time of attaching the lower, don't pass through events
            passthroughEvents = false
        }
        self.lower = try lowerProtocol.attachUpperDatagramProtocol(
            effectiveSelfReference,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public func invokeReceiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
        try lower.invokeReceiveDatagrams(effectiveSelfReference, maximumDatagramCount: maximumDatagramCount)
    }
    @inline(__always)
    public func invokeGetDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        try lower.invokeGetDatagramsToSend(
            effectiveSelfReference,
            maximumDatagramCount: maximumDatagramCount,
            minimumDatagramSize: minimumDatagramSize
        )
    }

    public func invokeSendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError) {
        try lower.invokeSendDatagrams(effectiveSelfReference, datagrams: datagrams)
    }
}

extension OneToOneDatagramProtocol where Self: ~Copyable {
    public mutating func receiveDatagrams(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveDatagrams(maximumDatagramCount: maximumDatagramCount)
    }
    public mutating func getDatagramsToSend(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
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
        guard passthroughEvents || isConnected else {
            datagrams.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendDatagrams(datagrams)
    }
}

extension OneToOneProtocolHandler where Self: ~Copyable, LowerProtocol == OutboundStreamLinkage {
    public mutating func attachLowerStreamProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        guard lower.isDetached else {
            throw NetworkError.posix(EALREADY)
        }
        if upper.isDetached {
            // If the upper is detached at the time of attaching the lower, don't pass through events
            passthroughEvents = false
        }
        self.lower = try lowerProtocol.attachUpperStreamProtocol(
            effectiveSelfReference,
            remote: remote,
            local: local,
            parameters: parameters,
            path: path
        )
    }

    public mutating func invokeReceiveStreamData(
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        try lower.invokeReceiveStreamData(
            effectiveSelfReference,
            minimumBytes: minimumBytes,
            maximumBytes: maximumBytes
        )
    }
    public mutating func invokeGetOutboundStreamDataRoomAvailable() throws(NetworkError) -> Int {
        try lower.invokeGetOutboundStreamDataRoomAvailable(effectiveSelfReference)
    }
    public mutating func invokeSendStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try lower.invokeSendStreamData(effectiveSelfReference, streamData: streamData)
    }
    public mutating func invokeSendEarlyStreamData(_ streamData: consuming FrameArray) throws(NetworkError) {
        try lower.invokeSendEarlyStreamData(effectiveSelfReference, streamData: streamData)
    }
}

extension OneToOneStreamToDatagramProtocol where Self: ~Copyable {
    public mutating func receiveStreamData(
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveStreamData(minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }
    public mutating func getOutboundStreamDataRoomAvailable(
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
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
        guard passthroughEvents || isConnected else {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendStreamData(streamData)
    }
}

extension OneToOneStreamProtocol where Self: ~Copyable {
    public mutating func receiveStreamData(
        _ from: ProtocolInstanceReference,
        minimumBytes: Int,
        maximumBytes: Int
    ) throws(NetworkError) -> FrameArray? {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
        return try self.receiveStreamData(minimumBytes: minimumBytes, maximumBytes: maximumBytes)
    }
    public mutating func getOutboundStreamDataRoomAvailable(
        _ from: ProtocolInstanceReference
    ) throws(NetworkError) -> Int {
        do { try validate(upper: from, #function) } catch { throw NetworkError.posix(EINVAL) }
        guard passthroughEvents || isConnected else { throw NetworkError.posix(ENOTCONN) }
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
        guard passthroughEvents || isConnected else {
            streamData.finalizeAllFramesAsFailed()
            throw NetworkError.posix(ENOTCONN)
        }
        try self.sendStreamData(streamData)
    }

    public mutating func handleInboundAbortedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleInboundAbortedEvent(error: error)
    }

    public mutating func handleOutboundAbortedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        do { try validate(lower: from, #function) } catch { return }
        self.handleOutboundAbortedEvent(error: error)
    }

    // Default implementations
    public mutating func handleInboundAbortedEvent(error: NetworkError?) {}
    public mutating func handleOutboundAbortedEvent(error: NetworkError?) {}
}
