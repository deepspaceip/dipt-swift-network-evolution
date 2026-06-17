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

#if canImport(BasicContainers)
import BasicContainers
internal import DequeModule
#endif

// This index is used to refer to a location (as in NetworkGappyArray) without
// exposing numeric properties
struct NetworkStateIndex: Hashable {
    fileprivate let index: Int
    fileprivate init(index: Int) {
        self.index = index
    }
    var rawValue: Int { index }
}

// A "gappy array" is an array of non-copyable elements where the index of
// an element does not change once it is added. The index will remain until
// the element is removed. When the element is removed, this can create a
// "gap" in the array which can be re-used by new elements.
//
// This type does not convey any particular order, but is used to be a condensed
// way of holding elements that have fast lookup. This is similar to how
// interface indices (if_index) is used in kernel networking stacks.
@available(Network 0.1.0, *)
struct NetworkGappyArray<Element: ~Copyable>: ~Copyable {

    // Array of elements, which may have gaps
    fileprivate var elements = NetworkUniqueArray<Element?>()

    // Free indices in elements array
    fileprivate var gaps = NetworkPriorityQueue<GapRecord>()

    @inlinable
    subscript(position: NetworkStateIndex) -> Element {
        _modify {
            yield &elements[position.index]!
        }
        mutating _read {
            yield elements[position.index]!
        }
    }

    var count: Int { elements.count - gaps.count }

    var isEmpty: Bool { count == 0 }

    internal struct GapRecord: ~Copyable, NetworkComparable {
        let index: NetworkStateIndex
        init(_ index: NetworkStateIndex) {
            self.index = index
        }

        static func < (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            lhs.index.index < rhs.index.index
        }
        static func == (lhs: borrowing Self, rhs: borrowing Self) -> Bool {
            (lhs.index.index == rhs.index.index)
        }
    }

    mutating func insert(_ element: consuming Element) -> NetworkStateIndex {
        if let gap = gaps.pop() {
            let gapIndex = gap.index
            elements[gapIndex.index] = consume element
            return gapIndex
        }
        let newIndex = elements.count
        elements.append(element)
        return NetworkStateIndex(index: newIndex)
    }

    internal mutating func cleanupGapsIfNecessary() {
        let count = elements.count
        guard count > 0, elements[count - 1] == nil else {
            // Cannot cleanup gaps at the end
            return
        }

        guard gaps.count * 10 > elements.count else {
            // Only cleanup gaps if they represent more than 10% of the total elements
            return
        }

        // Walk elements from end, removing any that are nil, and remove
        // the corresponding gap record
        while true {
            let count = elements.count
            guard count > 0 else { break }  // Array must be non-empty
            guard elements[count - 1] == nil else { break }  // Value must be nil
            gaps.removeFirst { $0.index.index == count - 1 }
            elements.removeLast()
        }
    }

    mutating func remove(index: NetworkStateIndex) {
        defer { cleanupGapsIfNecessary() }
        if index.index == elements.count - 1 {
            // Removing last element
            elements.removeLast()
            return
        }

        // Clear element and record the gap
        elements[index.index] = nil
        gaps.push(GapRecord(index))
    }
}
