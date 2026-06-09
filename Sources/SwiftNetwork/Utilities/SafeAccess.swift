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

#if !hasFeature(Embedded)

enum SafeAccess {

    /// Access a c structure from a raw buffer pointer.
    /// NOTE: The structure will be loaded aligned and will return nil if misaligned.
    ///
    /// Example usage:
    /// let headerBuffer = UnsafeRawBufferPointer(pointer)
    /// guard let cstruct = self.loadCStructure(buffer: headerBuffer, type: cstruct.self) else {
    ///    continue
    /// }
    static func loadCStructure<T>(buffer: UnsafeRawBufferPointer, type: T.Type) -> T? {

        let size = MemoryLayout<T>.size
        if buffer.count < size {
            return nil
        }
        if Int(bitPattern: buffer.baseAddress) & (MemoryLayout<T>.alignment - 1) == 0 {
            return buffer.baseAddress!.load(as: T.self)
        }
        return nil
    }
}

#endif
