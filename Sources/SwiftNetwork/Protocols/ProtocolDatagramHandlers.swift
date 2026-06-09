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

// MARK: Automatic Datagram Processing

/// Add conformance to `AutomaticLowerDatagramProcessing` to automatically send and receive datagrams
/// from lower protocols.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol AutomaticLowerDatagramProcessing: ~Copyable, InboundDatagramHandler {
    var lower: LowerProtocol { get set }

    /// A queue of datagrams that will be sent to the lower protocol.
    /// NOTE: Protocols generally do not need to access this directly.
    /// Instead, call `addToLowerSendQueue`.
    var lowerSendQueue: FrameArray { get set }

    /// A queue of datagrams that have been received from the lower protocol.
    /// NOTE: Protocols should access frames from this queue in response
    /// to the `serviceLowerReceiveQueue` call.
    var lowerReceiveQueue: FrameArray { get set }

    /// A function called when the lower protocol has added datagrams to
    /// `lowerReceiveQueue`.
    /// NOTE: Protocols should implement this function to customize behavior
    func serviceLowerReceiveQueue()

    /// A function called when there is outbound room available
    /// NOTE: Protocols should implement this function to customize behavior
    func handleOutboundRoomAvailable()
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension AutomaticLowerDatagramProcessing where Self: ~Copyable {
    /// A function to call to add datagrams to `lowerSendQueue`
    public mutating func addToLowerSendQueue(_ datagrams: consuming FrameArray) throws(NetworkError) {
        lowerSendQueue.add(frames: datagrams)
    }

    /// A function to call to indicate to the lower protocol that datagrams
    /// have been added to the `lowerSendQueue`.
    public mutating func serviceLowerSendQueue() {
        guard !lowerSendQueue.isEmpty else { return }
        try? lower.invokeSendDatagrams(reference, datagrams: lowerSendQueue.drainArray())
    }

    /// A function to call to indicate that datagrams should be read
    /// from the lower protocol.
    public mutating func resumeReadingInboundDatagrams() {
        _readInboundDatagrams()
    }
}

/// Add conformance to `AutomaticUpperDatagramProcessing` to automatically process datagrams
/// from upper protocols.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol AutomaticUpperDatagramProcessing: ~Copyable, OutboundDatagramHandler {
    var upper: UpperProtocol { get set }

    /// A queue of datagrams that have been sent by the upper protocol.
    /// NOTE: Protocols should access frames from this queue in response
    /// to the `serviceUpperSendQueue` call.
    var upperSendQueue: FrameArray { get set }

    /// A function called when the upper protocol has added datagrams to
    /// `upperSendQueue`.
    /// NOTE: Protocols should implement this function to customize behavior
    func serviceUpperSendQueue()

    /// A value to set to cap the maximum datagram size that the upper protocol
    /// will be allowed to send.
    var maximumUpperDatagramSize: Int { get set }

    /// A boolean to set if the upper protocol should be blocked from sending
    /// datagrams.
    var blockUpperSendQueue: Bool { get set }

    /// A queue of datagrams that will be delivered to the upper protocol.
    /// NOTE: Protocols generally do not need to access this directly.
    /// Instead, call `addToUpperReceiveQueue`.
    var upperReceiveQueue: FrameArray { get set }

}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension AutomaticUpperDatagramProcessing where Self: ~Copyable {
    /// A function to call to add datagrams to `upperReceiveQueue`
    public mutating func addToUpperReceiveQueue(_ datagrams: consuming FrameArray) throws(NetworkError) {
        upperReceiveQueue.add(frames: datagrams)
    }

    /// A function to call to indicate to the upper protocol that datagrams
    /// have been added to the `upperReceiveQueue`.
    public func serviceUpperReceiveQueue() {
        guard !upperReceiveQueue.isEmpty else { return }
        upper.deliverInboundDataAvailableEvent(reference)
    }
}

// MARK: Manual Datagram Processing

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol InboundDatagramHandler: ~Copyable, InboundDataHandler where LowerProtocol == OutboundDatagramLinkage {
    mutating func attachLowerDatagramProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError)
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol OutboundDatagramHandler: ~Copyable, OutboundDataHandler where UpperProtocol == InboundDatagramLinkage {

    mutating func attachUpperDatagramProtocol(
        _ from: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) -> OutboundDatagramLinkage

    mutating func receiveDatagrams(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray?
    mutating func getDatagramsToSend(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray?
    mutating func sendDatagrams(_ from: ProtocolInstanceReference, datagrams: consuming FrameArray) throws(NetworkError)
}

// MARK: Implementation Details

extension AutomaticLowerDatagramProcessing where Self: ~Copyable {
    mutating func _readInboundDatagrams() {
        var readCount = 0
        repeat {
            do throws(NetworkError) {
                let datagrams = try lower.invokeReceiveDatagrams(reference, maximumDatagramCount: Int.max)
                if let datagrams = consume datagrams {
                    readCount = datagrams.count
                    lowerReceiveQueue.add(frames: datagrams)
                } else {
                    readCount = 0
                }
            } catch {
                break
            }
            serviceLowerReceiveQueue()
            serviceLowerSendQueue()
        } while readCount != 0
    }

    mutating func handleInboundDataAvailableEvent() {
        _readInboundDatagrams()
    }

    mutating func handleOutboundRoomAvailableEvent() {
        serviceLowerSendQueue()
        handleOutboundRoomAvailable()
    }
}

extension AutomaticUpperDatagramProcessing where Self: ~Copyable {
    internal func newOutboundFrame(_ dataSize: Int) -> Frame {
        Frame(count: dataSize)
    }

    public mutating func receiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? {
        guard !upperReceiveQueue.isEmpty else { return nil }
        return upperReceiveQueue.drainArray(maximumFrameCount: maximumDatagramCount)
    }

    public func getDatagramsToSend(
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !blockUpperSendQueue else { return nil }
        let datagramSize: Int
        if maximumUpperDatagramSize == 0 {
            datagramSize = minimumDatagramSize
        } else {
            datagramSize = min(minimumDatagramSize, maximumUpperDatagramSize)
        }
        var returnArray = FrameArray(capacity: maximumDatagramCount)
        for _ in 0..<maximumDatagramCount {
            returnArray.add(frame: newOutboundFrame(datagramSize))
        }
        return returnArray
    }

    public mutating func sendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError) {
        upperSendQueue.add(frames: datagrams)
        serviceUpperSendQueue()
    }
}

extension ProtocolInstanceReference {
    func receiveDatagrams(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !isNone else { return nil }
        return try self.handleCallFromUpperProtocol { () throws(NetworkError) in
            switch self.reference {
            case .none: return nil
            case .udp(let index):
                return try context.udpInstances[index].receiveDatagrams(
                    from,
                    maximumDatagramCount: maximumDatagramCount
                )
            case .ip(let index):
                return try context.ipInstances[index].receiveDatagrams(from, maximumDatagramCount: maximumDatagramCount)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicDatagram(var instance):
                return try instance.receiveDatagrams(from, maximumDatagramCount: maximumDatagramCount)
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                return try instance.receiveDatagrams(from, maximumDatagramCount: maximumDatagramCount)
            #endif
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return try container.accessOutboundDatagramHandler(at: index) { instance throws(NetworkError) in
                    try instance.receiveDatagrams(from, maximumDatagramCount: maximumDatagramCount)
                }
            #endif
            default: fatalError("Protocol cannot accept receiveDatagrams call")
            }
        }
    }

    func getDatagramsToSend(
        _ from: ProtocolInstanceReference,
        maximumDatagramCount: Int,
        minimumDatagramSize: Int
    ) throws(NetworkError) -> FrameArray? {
        guard !isNone else { return nil }
        return try self.handleCallFromUpperProtocol { () throws(NetworkError) in
            switch self.reference {
            case .none: return nil
            case .udp(let index):
                return try context.udpInstances[index].getDatagramsToSend(
                    from,
                    maximumDatagramCount: maximumDatagramCount,
                    minimumDatagramSize: minimumDatagramSize
                )
            case .ip(let index):
                return try context.ipInstances[index].getDatagramsToSend(
                    from,
                    maximumDatagramCount: maximumDatagramCount,
                    minimumDatagramSize: minimumDatagramSize
                )
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicDatagram(let instance):
                return try instance.getDatagramsToSend(
                    from,
                    maximumDatagramCount: maximumDatagramCount,
                    minimumDatagramSize: minimumDatagramSize
                )
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance):
                return try instance.getDatagramsToSend(
                    from,
                    maximumDatagramCount: maximumDatagramCount,
                    minimumDatagramSize: minimumDatagramSize
                )
            #endif
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                return try container.accessOutboundDatagramHandler(at: index) { instance throws(NetworkError) in
                    try instance.getDatagramsToSend(
                        from,
                        maximumDatagramCount: maximumDatagramCount,
                        minimumDatagramSize: minimumDatagramSize
                    )
                }
            #endif
            default: fatalError("Protocol cannot accept getDatagramsToSend call")
            }
        }
    }

    func sendDatagrams(_ from: ProtocolInstanceReference, datagrams: consuming FrameArray) throws(NetworkError) {
        guard !isNone else {
            datagrams.finalizeAllFramesAsFailed()
            return
        }
        try self.handleCallFromUpperProtocol(datagrams) { datagrams throws(NetworkError) in
            switch self.reference {
            case .none:
                var datagrams = datagrams
                datagrams.finalizeAllFramesAsFailed()
                return
            case .udp(let index): try context.udpInstances[index].sendDatagrams(from, datagrams: datagrams)
            case .ip(let index): try context.ipInstances[index].sendDatagrams(from, datagrams: datagrams)
            #if !NETWORK_NO_SWIFT_QUIC
            case .quicDatagram(var instance): try instance.sendDatagrams(from, datagrams: datagrams)
            #if !NETWORK_NO_TESTING_HARNESS
            case .datagramLowerHarness(var instance): try instance.sendDatagrams(from, datagrams: datagrams)
            #endif
            #endif
            #if !NETWORK_EMBEDDED
            case .custom(let container, let index):
                try container.accessOutboundDatagramHandler(at: index, datagrams) {
                    instance,
                    datagrams throws(NetworkError) in
                    try instance.sendDatagrams(from, datagrams: datagrams)
                }
            #endif
            default: fatalError("Protocol cannot accept sendDatagrams call")
            }
        }
    }
}
