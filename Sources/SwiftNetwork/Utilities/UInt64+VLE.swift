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

enum VariableLengthEncodingError: Int, Error {
    case invalidValue
    case bufferTooShort
}

extension FixedWidthInteger {
    var safeVariableLengthSize: Int? {
        // RFC 9000 Section 16
        if self <= 63 { return 1 }
        if self <= 16383 { return 2 }
        if self <= 1_073_741_823 { return 4 }
        if UInt64(self) <= UInt64(4_611_686_018_427_387_903) { return 8 }
        return nil
    }

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    var variableLengthSize: Int {
        guard let size = self.safeVariableLengthSize else {
            Logger.proto.error("Integer value too large to encode into a 8-byte VLE")
            return 8
        }
        return size
    }
}

extension UInt64 {
    var safeVariableLengthSize: Int? {
        // RFC 9000 Section 16
        if self <= 63 { return 1 }
        if self <= 16383 { return 2 }
        if self <= 1_073_741_823 { return 4 }
        if self <= 4_611_686_018_427_387_903 { return 8 }
        return nil
    }
    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    @inline(__always)
    var variableLengthSize: Int {
        guard let size = self.safeVariableLengthSize else {
            Logger.proto.error("Integer value too large to encode into a 8-byte VLE")
            return 8
        }
        return size
    }
}

extension UInt64 {
    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    func variableLengthEncodeInto(_ buffer: inout [UInt8]) {
        guard let length = self.safeVariableLengthSize else {
            // Too big, encode the max UInt62 value instead
            Logger.proto.error("Integer value too large to encode into a 8-byte VLE, setting to UInt62 max")
            UInt64(4_611_686_018_427_387_903).variableLengthEncodeInto(&buffer)
            return
        }
        var value: UInt64

        switch length {
        case 1:
            value = self
            withUnsafeBytes(of: UInt8(value)) { buffer.append(contentsOf: $0) }
        case 2:
            value = (1 << 14 | self)
            withUnsafeBytes(of: UInt16(value).bigEndian) { buffer.append(contentsOf: $0) }
        case 4:
            value = (1 << 31 | self)
            withUnsafeBytes(of: UInt32(value).bigEndian) { buffer.append(contentsOf: $0) }
        default:
            value = (3 << 62 | self)
            withUnsafeBytes(of: UInt64(value).bigEndian) { buffer.append(contentsOf: $0) }
        }
    }

    @available(macOS 10.14.4, iOS 12.2, tvOS 12.2, watchOS 5.2, *)
    @discardableResult
    func variableLengthEncodeInto(
        _ bytes: inout MutableRawSpan,
        offset: Int = 0
    ) throws(VariableLengthEncodingError) -> Int {
        guard let length = self.safeVariableLengthSize else {
            throw VariableLengthEncodingError.invalidValue
        }
        guard offset + length <= bytes.byteCount else {
            throw VariableLengthEncodingError.bufferTooShort
        }
        var value: UInt64

        switch length {
        case 1:
            value = self
            bytes.storeBytes(of: UInt8(value), toByteOffset: offset, as: UInt8.self)
        case 2:
            value = (1 << 14 | self)
            bytes.storeBytes(of: UInt16(value).bigEndian, toByteOffset: offset, as: UInt16.self)
        case 4:
            value = (1 << 31 | self)
            bytes.storeBytes(of: UInt32(value).bigEndian, toByteOffset: offset, as: UInt32.self)
        default:
            value = (3 << 62 | self)
            bytes.storeBytes(of: UInt64(value).bigEndian, toByteOffset: offset, as: UInt64.self)
        }
        return length
    }

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, *)
    func variableLengthValidateInBuffer(_ buffer: RawSpan, offset: Int = 0) throws(VariableLengthEncodingError) -> Int {
        let length = self.variableLengthSize
        guard offset + length <= buffer.byteCount else {
            throw VariableLengthEncodingError.bufferTooShort
        }

        switch length {
        case 1:
            let expectedValue = UInt8(self)
            let readValue = buffer.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt8.self)
            guard expectedValue == readValue else {
                throw VariableLengthEncodingError.invalidValue
            }
        case 2:
            let expectedValue = UInt16(1 << 14 | self).bigEndian
            let readValue = buffer.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt16.self)
            guard expectedValue == readValue else {
                throw VariableLengthEncodingError.invalidValue
            }
        case 4:
            let expectedValue = UInt32(1 << 31 | self).bigEndian
            let readValue = buffer.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt32.self)
            guard expectedValue == readValue else {
                throw VariableLengthEncodingError.invalidValue
            }
        default:
            let expectedValue = UInt64(3 << 62 | self).bigEndian
            let readValue = buffer.unsafeLoadUnaligned(fromByteOffset: offset, as: UInt64.self)
            guard expectedValue == readValue else {
                throw VariableLengthEncodingError.invalidValue
            }
        }
        return length
    }
}
