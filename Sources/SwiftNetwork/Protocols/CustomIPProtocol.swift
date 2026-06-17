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

@_spi(Essentials)
@available(Network 0.1.0, *)
public struct CustomIPProtocol: NetworkProtocol {
    public typealias Options = CustomIPOptions
    public typealias Metadata = CustomIPMetadata
    typealias Instance = CustomIPInstance

    public struct CustomIPOptions: PerProtocolOptions {
        var ipProtocolNumber: UInt8 = 0
        init() {}

        init?(from serializedBytes: [UInt8]) {
            var ipProtocolNumber: UInt8 = 0
            let result = Deserializer.deserialize(serializedBytes.span) { read throws(DeserializationError) in
                try read.uint8(&ipProtocolNumber)
            }
            guard case .success = result else {
                Logger.proto.error("Failed to deserialize: \(result)")
                return nil
            }
            self.ipProtocolNumber = ipProtocolNumber
        }
        public func serialize() -> [UInt8]? {
            Serializer.serialize { write in
                write.uint8(ipProtocolNumber)
            }
        }
        public var serializeInParameters: Bool {
            false
        }
        public func deepCopy() -> CustomIPOptions {
            self
        }
        public func isEqual(to other: CustomIPOptions, for: ProtocolCompareMode) -> Bool {
            self == other
        }
    }

    public struct CustomIPMetadata: PerProtocolMetadata {
        init() {}
        public func isEqual(to other: CustomIPMetadata, for: ProtocolCompareMode) -> Bool {
            true
        }
    }

    final class CustomIPInstance: OneToOneDatagramProtocol, ProtocolInstanceContainer {
        var upper = InboundDatagramLinkage()
        var lower = OutboundDatagramLinkage()

        private(set) var context: NetworkContext
        init(context: NetworkContext) { self.context = context }
        var reference: ProtocolInstanceReference { ProtocolInstanceReference(custom: self) }
        var passthroughEvents = false
        var log = NetworkLoggerState()
        var eventManager = ProtocolEventManager()

        func setup(
            remote: Endpoint?,
            local: Endpoint?,
            parameters: Parameters?,
            path: PathProperties?
        ) throws(NetworkError) {
            throw NetworkError.posix(ENOTSUP)
        }
        func receiveDatagrams(maximumDatagramCount: Int) throws(NetworkError) -> FrameArray? { nil }
        func getDatagramsToSend(maximumDatagramCount: Int, minimumDatagramSize: Int) throws(NetworkError) -> FrameArray?
        { nil }
        func sendDatagrams(_ datagrams: consuming FrameArray) throws(NetworkError) {}
        #if !NETWORK_EMBEDDED
        var metadata: AbstractProtocolMetadata? { nil }
        #endif
    }

    public init() {}
    public func newPerProtocolOptions() -> Options? { Options() }
    public func newPerProtocolOptions(from existing: Options) -> Options { existing }
    public func newPerProtocolOptions(from serializedBytes: [UInt8]) -> Options? { Options(from: serializedBytes) }
    public func newPerProtocolMetadata() -> Metadata? { Metadata() }
    public func newProtocolInstance(context: NetworkContext) -> ProtocolInstanceReference? {
        Instance(context: context).reference
    }

    static let identifier = ProtocolIdentifier(name: "custom-ip", level: .transport, mapping: .oneToOne)

    #if !NETWORK_PRIVATE
    static let definition = ProtocolDefinition<CustomIPProtocol>(identifier: identifier)
    #endif

    static public func options(protocolNumber: UInt8) -> ProtocolOptions<CustomIPProtocol> {
        let options = CustomIPProtocol.definition.protocolOptions()
        options.ipProtocolNumber = protocolNumber
        return options
    }

    static public func instance(context: NetworkContext) -> ProtocolInstanceReference {
        CustomIPProtocol().newProtocolInstance(context: context)!
    }
}

@available(Network 0.1.0, *)
extension ProtocolOptions<CustomIPProtocol> {
    var ipProtocolNumber: UInt8 {
        get { perProtocolOptions!.ipProtocolNumber }
        set { perProtocolOptions!.ipProtocolNumber = newValue }
    }
}
