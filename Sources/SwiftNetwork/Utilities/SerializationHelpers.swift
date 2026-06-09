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

// MARK: - DeserializerSpanFactory

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol DeserializerSpanFactory: ~Copyable, ~Escapable {
    /// Access the next span from the factory.
    @_lifetime(&self)
    mutating func nextSpan() -> RawSpan?

    /// Access the total available byte count across all spans that this factory can emit.
    var availableByteCount: Int { get }
}

/// A factory that stores a single span.
/// Used when the Deserializer is initialized directly from a RawSpan.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct SingleSpanFactory: ~Escapable, DeserializerSpanFactory {
    private var span: RawSpan
    private var consumed: Bool = false

    @_lifetime(copy span)
    init(_ span: RawSpan) {
        self.span = span
    }

    @_lifetime(&self)
    public mutating func nextSpan() -> RawSpan? {
        guard !consumed else { return nil }
        consumed = true
        return span
    }

    public var availableByteCount: Int {
        span.byteCount
    }
}

// MARK: - SerializerSpanFactory

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public protocol SerializerSpanFactory: ~Copyable, ~Escapable {
    /// Access the next span from the factory.
    @_lifetime(&self)
    mutating func nextMutableSpan() -> MutableRawSpan?

    /// Access the total available byte count across all spans that this factory can emit.
    var availableByteCount: Int { get }
}

/// A factory that stores a single mutable span.
/// Used when the Serializer is initialized directly from a MutableRawSpan.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct SingleMutableSpanFactory: ~Copyable, ~Escapable, SerializerSpanFactory {
    private var span: MutableSpan<UInt8>
    private var consumed: Bool = false

    @_lifetime(copy span)
    init(_ span: consuming MutableSpan<UInt8>) {
        self.span = span
    }

    @_lifetime(&self)
    public mutating func nextMutableSpan() -> MutableRawSpan? {
        guard !consumed else { return nil }
        consumed = true
        return span.mutableBytes
    }

    public var availableByteCount: Int {
        span.count
    }
}

#if !NETWORK_EMBEDDED

// MARK: - FrameArraySpanFactory

/// A span factory that walks across the frames in a FrameArray,
/// providing each frame's bytes as a span and optionally claiming
/// consumed bytes from each frame.
@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct FrameArraySpanFactory: ~Copyable, ~Escapable, DeserializerSpanFactory {
    private var frameArray: FrameArray
    private var spanIndex = 0
    private var spanCount: Int
    public private(set) var availableByteCount: Int

    /// Extract the frame array from the factory, consuming it in the process.
    consuming func takeFrameArray() -> FrameArray {
        frameArray
    }

    public mutating func drainArray(maximumByteCount: Int) -> FrameArray {
        let removedFrames = frameArray.drainArray(maximumByteCount: maximumByteCount)

        // Reset internal counters
        spanCount = frameArray.count
        availableByteCount = frameArray.unclaimedLength
        spanIndex = 0

        return removedFrames
    }

    // The factory owns the FrameArray (consumed in), so it has no external
    // lifetime dependency. @_lifetime(immortal) is correct for a self-contained
    // ~Escapable type whose data is fully owned.
    @_lifetime(immortal)
    init(_ frameArray: consuming FrameArray) {
        self.spanCount = frameArray.count
        self.availableByteCount = frameArray.unclaimedLength
        self.frameArray = frameArray
    }

    @_lifetime(&self)
    public mutating func nextSpan() -> RawSpan? {
        // Check if we're out of spans
        guard spanIndex < spanCount else {
            return nil
        }

        let currentIndex = spanIndex

        // Advance to the next span
        spanIndex += 1

        return _overrideLifetime(frameArray.bytes(at: currentIndex), borrowing: self)
    }
}

#endif
