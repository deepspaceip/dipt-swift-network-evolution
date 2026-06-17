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

#if IMPORT_SWIFTTLS && canImport(SwiftTLS)

@_spi(Essentials) @_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public final class NewFlowPerfTestHandler: ProtocolInstanceContainer, InboundFlowHandler, LoggableProtocol {

    public typealias LowerProtocol = StreamListenerLinkage
    typealias UpperStreamHandlerType = StreamPerfTestHandler

    // Public mutable state
    public var eventManager = ProtocolEventManager()
    public var log = NetworkLoggerState("[NewFlowHandler]")
    public var reference: ProtocolInstanceReference { ProtocolInstanceReference(custom: self) }
    public var context: NetworkContext
    public var streams: [StreamPerfTestHandler] = []
    public var connectedHandler: ((Bool) -> Void)?

    // Private constant state
    let local: Endpoint
    let remote: Endpoint
    let parameters: Parameters
    let path: PathProperties
    let logger: LoggingHandle

    // Private mutable state
    private var newFlowHandler: ((StreamPerfTestHandler) -> Void)?
    private var errorHandler: ((NetworkError) -> Void)?
    private var lowerProtocol = LowerProtocol(reference: .init())

    public init?(
        local: Endpoint,
        remote: Endpoint,
        parameters: Parameters,
        path: PathProperties,
        logger: LoggingHandle,
        streamListenerProtocol: StreamListenerLinkage
    ) {
        self.local = local
        self.remote = remote
        self.parameters = parameters
        self.path = path
        self.logger = logger
        self.context = parameters.context
        do throws(NetworkError) {
            self.lowerProtocol = try streamListenerProtocol.invokeAttachNewStreamFlowProtocol(
                self.reference,
                remote: remote,
                local: local,
                parameters: parameters,
                path: path
            )
        } catch {
            return nil
        }
    }

    func log(_ logMessage: @autoclosure () -> String) {
        guard self.logger.loggingType != .none else { return }
        let message = logMessage()
        self.logger.log("\(self.log.logPrefix) \(message)")
    }

    public func setNewFlowHandler(newFlowHandler: @escaping (StreamPerfTestHandler) -> Void) {
        self.newFlowHandler = newFlowHandler
    }

    public func setErrorHandler(errorHandler: @escaping (NetworkError) -> Void) {
        self.errorHandler = errorHandler
    }

    // Start the new flow handler
    func start() {
        log("start")
        fromExternal {
            self.lowerProtocol.invokeConnect(reference)
        }
    }

    public func start(_ completion: @escaping (Bool) -> Void) {
        self.connectedHandler = completion
        start()
    }

    // Stop the new flow handler
    func stop() {
        log("stop")
        fromExternal {
            self.lowerProtocol.invokeDisconnect(reference)
        }
    }

    // Teardown the new flow handler
    public func teardown() {
        fromExternal {
            do throws(NetworkError) {
                try lowerProtocol.invokeDetach(reference)
                self.lowerProtocol = .init(reference: .init())
            } catch {
                log("Failed to detach lower protocol: \(error)")
            }
        }
    }

    // Received connected event
    public func handleConnectedEvent(_ from: ProtocolInstanceReference) {
        log("connected received")
        if let completion = connectedHandler {
            completion(true)
            self.connectedHandler = nil
        }
    }

    // Received disconnected event
    public func handleDisconnectedEvent(_ from: ProtocolInstanceReference, error: NetworkError?) {
        log("received disconnected with error: \(String(describing: error))")
    }

    public func handleNetworkProtocolEvent(_ from: ProtocolInstanceReference, event: NetworkProtocolEvent) {
        log("received network protocol event: \(event)")
    }

    // Receive a new inbound flow to create a StreamPerfTestHandler from.
    public func handleNewInboundFlowEvent(
        _ from: ProtocolInstanceReference,
        flowReference: ProtocolInstanceReference,
        flowMetadata: AbstractProtocolMetadata?
    ) {
        log("received new inbound flow")
        do throws(NetworkError) {
            let streamHandler = StreamPerfTestHandler(
                identifier: "Server",
                local: self.local,
                remote: self.remote,
                parameters: self.parameters,
                path: self.path,
                streamID: 0,  // Just used to seed initial stream id
                logger: self.logger
            )
            streamHandler.lowerProtocol = try lowerProtocol.invokeAttachUpperStreamProtocolToExistingFlow(
                streamHandler.reference,
                flowReference: flowReference
            )
            // Update with the new stream id after the new input handler is created
            if let metadata = flowMetadata as? ProtocolMetadata<QUICProtocol>,
                let inputHandlerStreamID = metadata.streamID
            {
                log("Setting new stream id: \(inputHandlerStreamID) for new inbound flow")
                streamHandler.setStreamID(streamID: inputHandlerStreamID)
            }
            if let errorHandler = streamHandler.errorHandler {
                streamHandler.setErrorHandler(errorHandler: errorHandler)
            }
            streamHandler.start()
            guard let newFlowHandler = self.newFlowHandler else {
                return
            }
            self.streams.append(streamHandler)
            newFlowHandler(streamHandler)
        } catch {
            log("Failed to attach new inbound flow")
            return
        }
    }
}

@available(Network 0.1.0, *)
extension NewFlowPerfTestHandler: UpperProtocolHandler {
    // Conform to UpperProtocolHandler but the function is unused
    public func attachLowerProtocol(
        _ lowerProtocol: ProtocolInstanceReference,
        remote: Endpoint?,
        local: Endpoint?,
        parameters: Parameters?,
        path: PathProperties?
    ) throws(NetworkError) {
        throw NetworkError.posix(EINVAL)
    }
}
#endif
