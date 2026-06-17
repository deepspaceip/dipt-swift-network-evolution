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

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public final class DatagramPerfTestHandler: ProtocolInstanceContainer, InboundDatagramHandler, LoggableProtocol {

    public typealias LowerProtocol = OutboundDatagramLinkage

    // Private Constant state
    private let local: Endpoint
    private let remote: Endpoint
    private let parameters: Parameters
    private let path: PathProperties
    private let logger: LoggingHandle
    private let identifier: String

    // Public mutable state
    public var log = NetworkLoggerState()
    public var reference: ProtocolInstanceReference { ProtocolInstanceReference(custom: self) }
    public var eventManager = ProtocolEventManager()
    public var context: NetworkContext
    public var connected: Bool = false
    public var readAvailable: Bool = true
    public var connectedHandler: ((Bool) -> Void)?

    // Internal mutable state
    internal var errorHandler: ((NetworkError) -> Void)?
    internal var lowerProtocol = LowerProtocol(reference: .init())

    public init(
        identifier: String,
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        logger: LoggingHandle
    ) {
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        self.logger = logger
        self.context = parameters.context
        self.identifier = identifier
        log.logPrefix = "[\(identifier)]"
    }

    public init?(
        identifier: String,
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        logger: LoggingHandle,
        lowerProtocol: OutboundDatagramLinkage
    ) {
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        self.logger = logger
        self.context = parameters.context
        self.identifier = identifier
        log.logPrefix = "[\(identifier)]"
        do throws(NetworkError) {
            self.lowerProtocol = try lowerProtocol.invokeAttachUpperDatagramProtocol(
                reference,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        } catch {
            self.log("Error attaching lower protocol: \(error)")
            return nil
        }
    }

    // Set an error callback for the stream handler to notify the connection that an error took place
    func setErrorHandler(errorHandler: @escaping (NetworkError) -> Void) {
        self.errorHandler = errorHandler
    }

    func log(_ logMessage: @autoclosure () -> String) {
        guard self.logger.loggingType != .none else { return }
        let message = logMessage()
        self.logger.log("\(self.log.logPrefix) \(message)")
    }

    // Start the datagram handler
    public func start() {
        log("start")
        fromExternal {
            lowerProtocol.invokeConnect(reference)
        }
    }

    public func start(_ completion: @escaping (Bool) -> Void) {
        connectedHandler = completion
        start()
    }

    // Stop and disconnect the datagram handler
    public func stop() {
        log("stop")
        self.connected = false
        self.readAvailable = false
        fromExternal {
            lowerProtocol.invokeDisconnect(reference)
        }
    }

    public func teardown() {
        log("teardown")
        fromExternal {
            do throws(NetworkError) {
                try lowerProtocol.invokeDetach(reference)
                lowerProtocol = .init(reference: .init())
            } catch {
                log("Failed to detach lower protocol: \(error)")
            }
        }
    }

    // Called when the stream handler receives an error and is stopping/disconnecting
    public func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        log("handleDisconnectedEvent error: \(String(describing: error))")
        guard let errorHandler = self.errorHandler,
            let networkError = error
        else {
            return
        }
        errorHandler(networkError)
    }

    public func handleInboundDataAvailableEvent(_ from: ProtocolInstanceReference) {
        if !self.connected { return }
        // If input is available, read right away and buffer any available application data until its picked up by the state machine in readDataForStream
        log("received input room available")
        self.readAvailable = true
    }

    public func handleOutboundRoomAvailableEvent(_ from: ProtocolInstanceReference) {
        log("received output available")
    }

    public func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent) {
        log("received network protocol event: \(event)")
    }

    // Stream handler is in the connected state
    public func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        log("connected")
        if let completion = connectedHandler {
            completion(true)
            self.connectedHandler = nil
        }
        // Set this flag at the end of the connected function to make sure the client waits long enough until the key state is ready to send data.
        self.connected = true
    }

    public func write(_ datagram: [UInt8]) -> Bool {
        fromExternal {
            do throws(NetworkError) {
                let frames = try lowerProtocol.invokeGetDatagramsToSend(
                    reference,
                    maximumDatagramCount: 1,
                    minimumDatagramSize: datagram.count
                )
                guard var frames = frames else {
                    log.error("Failed to get datagram to send")
                    return false
                }
                frames.iterateMutableFrames { frame in
                    let result = Serializer.serialize(&frame, claim: true) { write throws(SerializationError) in
                        try write.buffer(datagram)
                    }
                    log("Write result: \(result)")
                    frame.collapse()
                    if !frame.unclaim(fromStart: datagram.count) {
                        log.error("Failed to unclaim")
                    }
                    return false
                }
                try lowerProtocol.invokeSendDatagrams(reference, datagrams: frames)
                return true
            } catch {
                return false
            }
        }
    }

    public func read() -> [UInt8]? {
        fromExternal {
            do throws(NetworkError) {
                let frames = try lowerProtocol.invokeReceiveDatagrams(reference, maximumDatagramCount: 1)
                guard var frames = frames else {
                    log("Failed to receive datagrams")
                    return nil
                }
                var returnBuffer: [UInt8]? = nil
                frames.iterateMutableFrames { frame in
                    var buffer = [UInt8]()
                    let length = frame.unclaimedLength
                    if length > 0 {
                        _ = Deserializer.deserialize(&frame, claim: false) { read throws(DeserializationError) in
                            try read.buffer(&buffer, length: length)
                        }
                    }
                    returnBuffer = buffer
                    frame.finalize(success: true)
                    return true
                }
                return returnBuffer
            } catch {
                return nil
            }
        }
    }
}

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
extension DatagramPerfTestHandler: UpperProtocolHandler {

    // UpperProtocolHandler conformance
    public func attachLowerDatagramProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        throw NetworkError.posix(ENOTSUP)
    }

    // UpperProtocolHandler conformance
    public func attachLowerProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        throw NetworkError.posix(ENOTSUP)
    }
}
