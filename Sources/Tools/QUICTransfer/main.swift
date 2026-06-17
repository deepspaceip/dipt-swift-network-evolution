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
@_spi(Essentials) @_spi(ProtocolProvider) import SwiftNetworkBenchmarks
import Dispatch

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(os)
internal import os
#endif

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

#if IMPORT_SWIFTTLS && canImport(SwiftTLS)

@available(Network 0.1.0, *)
final class QUICTransfer {

    // 169.254.156.146
    let localIPv4Address: [UInt8] = [0xa9, 0xfe, 0x9c, 0x92]
    // 169.254.225.163
    let remoteIPv4Address: [UInt8] = [0xa9, 0xfe, 0xe1, 0xa3]

    let dataBenchmarkUtility = DataBenchmarkUtility()
    let quicBenchmakrUtility = QUICBenchmarkUtility()
    let NSEC_PER_MSEC = UInt64(Duration.milliseconds(1) / Duration.nanoseconds(1))
    var serverSigningKey = P256.Signing.PrivateKey()

    func run(iterations: Int, loggingHandle: LoggingHandle, group: DispatchGroup, sendSize: Int) -> Double {
        let ipv4Client = Endpoint(address: IPv4Address(localIPv4Address)!, port: 0)
        let ipv4Server = Endpoint(address: IPv4Address(remoteIPv4Address)!, port: 0)
        // Create a random payload to send back and forth
        var payload = [UInt8](repeating: 0, count: sendSize)
        payload = (0..<sendSize).map { _ in UInt8.random(in: 0...255) }
        var index = 0
        print("Running QUIC transfer, transferring \(iterations) packet\(iterations > 1 ? "s" : "")")
        let timestart = DispatchTime.now().uptimeNanoseconds

        group.enter()
        var clientParameters = Parameters()
        let context = NetworkContext(identifier: "QUICTransfer")
        clientParameters.context = context
        context.activate()
        context.async {
            // Client
            let path = PathProperties(parameters: clientParameters)
            let clientIP = IPProtocol.instance(context: clientParameters.context)
            let clientIPOptions = IPProtocol.options()
            clientIPOptions.setLogID(prefix: "C", parent: "1", protocolLogIDNumber: 3)
            clientIPOptions.setProtocolInstance(clientIP)
            clientParameters.defaultStack.internet = .ip(clientIPOptions)

            let clientUDP = UDPProtocol.instance(context: context)
            let clientUDPOptions = UDPProtocol.options()
            clientUDPOptions.noMetadata = true
            clientUDPOptions.setLogID(prefix: "C", parent: "1", protocolLogIDNumber: 2)
            clientUDPOptions.setProtocolInstance(clientUDP)
            clientParameters.defaultStack.transport = .udp(clientUDPOptions)

            let clientQUIC = QUICProtocol.instance(context: context)
            var clientTLSOptions = SwiftTLSProtocol.Options()
            clientTLSOptions.applicationProtocols = ["network_test"]
            clientTLSOptions.serverName = "quic-test.local"
            clientTLSOptions.trustedRawPublicKeyCertificates = [
                [UInt8](self.serverSigningKey.publicKey.derRepresentation)
            ]
            let clientQUICOptions = QUICStreamProtocol.options()
            clientQUICOptions.tlsOptions = clientTLSOptions
            clientQUICOptions.setLogID(prefix: "C", parent: "1", protocolLogIDNumber: 1)
            clientQUICOptions.setProtocolInstance(clientQUIC)
            clientParameters.defaultStack.prepend(applicationProtocol: .quic(clientQUICOptions))

            let clientListenerLinkage = StreamListenerLinkage(reference: clientQUIC)
            let clientInput = StreamUpperHarness(
                identifier: "Client",
                local: ipv4Client,
                remote: ipv4Server,
                parameters: clientParameters,
                path: path,
                context: context,
                listenerProtocol: clientListenerLinkage
            )
            guard let clientInput else {
                return
            }

            let clientOutput = DatagramLowerHarness(
                identifier: "Client",
                context: clientParameters.context
            )
            do {
                try clientQUIC.attachLowerDatagramProtocolForNewPath(
                    clientUDP,
                    remote: ipv4Server,
                    local: ipv4Client,
                    parameters: clientParameters,
                    path: path
                )
                try clientUDP.attachLowerDatagramProtocol(
                    clientIP,
                    remote: ipv4Server,
                    local: ipv4Client,
                    parameters: clientParameters,
                    path: path
                )
                try clientIP.attachLowerDatagramProtocol(
                    clientOutput.reference,
                    remote: ipv4Server,
                    local: ipv4Client,
                    parameters: clientParameters,
                    path: path
                )
            } catch {
                loggingHandle.log("Failed to attach client IP to lower protocol")
                return
            }
            // Server
            var serverParameters = Parameters()
            serverParameters.isServer = true
            serverParameters.context = context
            let serverPath = PathProperties(parameters: serverParameters)
            let serverIP = IPProtocol.instance(context: clientParameters.context)
            let serverIPOptions = IPProtocol.options()
            serverIPOptions.setLogID(prefix: "L", parent: "1", protocolLogIDNumber: 3)
            clientIPOptions.setProtocolInstance(serverIP)
            serverParameters.defaultStack.internet = .ip(serverIPOptions)

            let serverUDP = UDPProtocol.instance(context: context)
            let serverUDPOptions = UDPProtocol.options()
            serverUDPOptions.noMetadata = true
            serverUDPOptions.setLogID(prefix: "L", parent: "1", protocolLogIDNumber: 2)
            serverUDPOptions.setProtocolInstance(serverUDP)
            serverParameters.defaultStack.transport = .udp(serverUDPOptions)

            let serverQUIC = QUICProtocol.instance(context: context)
            var serverTLSOptions = SwiftTLSProtocol.Options()
            serverTLSOptions.applicationProtocols = ["network_test"]
            serverTLSOptions.serverName = "quic-test.local"
            serverTLSOptions.rawPrivateKey = [UInt8](self.serverSigningKey.rawRepresentation)

            let serverQUICOptions = QUICStreamProtocol.options()
            serverQUICOptions.tlsOptions = serverTLSOptions
            serverQUICOptions.setLogID(prefix: "L", parent: "1", protocolLogIDNumber: 1)
            serverQUICOptions.setProtocolInstance(serverQUIC)
            serverParameters.defaultStack.prepend(applicationProtocol: .quic(serverQUICOptions))

            let serverListenerLinkage = StreamListenerLinkage(reference: serverQUIC)
            let serverInput = NewStreamFlowHarness(
                identifier: "Server",
                local: ipv4Server,
                remote: ipv4Client,
                parameters: serverParameters,
                path: serverPath,
                context: serverParameters.context,
                listenerProtocol: serverListenerLinkage
            )
            guard let serverInput else {
                return
            }

            let serverOutput = DatagramLowerHarness(
                identifier: "Server",
                context: clientParameters.context
            )
            do {
                try serverQUIC.attachLowerDatagramProtocolForNewPath(
                    serverUDP,
                    remote: ipv4Client,
                    local: ipv4Server,
                    parameters: serverParameters,
                    path: serverPath
                )

                try serverUDP.attachLowerDatagramProtocol(
                    serverIP,
                    remote: ipv4Client,
                    local: ipv4Server,
                    parameters: clientParameters,
                    path: path
                )
                try serverIP.attachLowerDatagramProtocol(
                    serverOutput.reference,
                    remote: ipv4Client,
                    local: ipv4Server,
                    parameters: serverParameters,
                    path: serverPath
                )
            } catch {
                loggingHandle.log("Failed to attach server IP to lower protocol")
                return
            }
            var serverConnected: Bool = false
            serverInput.start { connected in
                serverConnected = connected
            }
            clientInput.start()
            // The client will complete TLS before the server
            while !serverConnected {
                let _ = self.dataBenchmarkUtility.loopOutputHandlerPackets(
                    sender: clientOutput,
                    receiver: serverOutput,
                    maximumBurst: 10
                )
                let _ = self.dataBenchmarkUtility.loopOutputHandlerPackets(
                    sender: serverOutput,
                    receiver: clientOutput,
                    maximumBurst: 10
                )
            }
            // Transfer all of the data
            for _ in 0..<iterations {
                group.enter()
                let writeSuccess = clientInput.write(payload)
                guard writeSuccess else {
                    group.leave()
                    print("Issue took place writing to the client")
                    break
                }
                var payloadReceived = false
                var readDataSize = 0
                while !payloadReceived {
                    let _ = self.dataBenchmarkUtility.loopOutputHandlerPackets(
                        sender: clientOutput,
                        receiver: serverOutput,
                        maximumBurst: 50
                    )
                    let _ = self.dataBenchmarkUtility.loopOutputHandlerPackets(
                        sender: serverOutput,
                        receiver: clientOutput,
                        maximumBurst: 50
                    )

                    if let readBytes = serverInput.upperHarnesses.first?.readAndDrop() {
                        readDataSize += readBytes
                        if readDataSize == sendSize {
                            payloadReceived = true
                        }
                    }
                }
                index += 1
                group.leave()
            }
            clientInput.stop()
            clientInput.teardown()
            serverInput.stop()
            serverInput.teardown()
            group.leave()
        }
        group.wait()
        print("Completed \(index) / \(iterations) transfers")
        // Short circuit and return 0 if index does not match iterations
        if index != iterations {
            return 0
        }
        // Get the elapsed time
        let endTime = DispatchTime.now().uptimeNanoseconds
        var totalTime = Double(endTime - timestart) / Double(NSEC_PER_MSEC)
        totalTime = (totalTime / 1000.0)
        return totalTime
    }
}

if #available(anyAppleOS 26, *) {
    // Take command line arguments
    var iterations = 10000  // 5gb total (if 500000 sendSize)
    var loggingHandler: LoggingHandle = LoggingHandle(loggingType: .none)
    var sendSize = 500000  // 500kb
    let arguments = CommandLine.arguments.dropFirst(0)
    if arguments.contains("-iterations"),
        let index = arguments.firstIndex(of: "-iterations")
    {
        if arguments.count >= (index + 2) {
            if let parsedIterations = Int(arguments[index + 1]) {
                iterations = parsedIterations
            }
        }
    }

    if arguments.contains("-logging"),
        let index = arguments.firstIndex(of: "-logging")
    {
        if arguments.count >= (index + 2) {
            let parsedLoggingOption = String(arguments[index + 1])
            loggingHandler = LoggingHandle(parsedLoggingOption)
        }
    }

    if arguments.contains("-size"),
        let index = arguments.firstIndex(of: "-size")
    {
        if arguments.count >= (index + 2) {
            if let sendSizeOption = Int(arguments[index + 1]) {
                sendSize = sendSizeOption
            }
        }
    }

    // Create and run the transfers
    let quicTransfer = QUICTransfer()
    let group = DispatchGroup()
    print("Starting \(iterations) transfers with logging set to \(loggingHandler)")
    let totalTime = quicTransfer.run(
        iterations: iterations,
        loggingHandle: loggingHandler,
        group: group,
        sendSize: sendSize
    )
    if totalTime > 0 {
        print("Finished all (\(iterations)) transfers in \(totalTime) seconds")
    } else {
        print("Error running all (\(iterations)) transfers, something failed")
    }
} else {
    fatalError("This tool requires macOS 26 or newer")
}

#endif
