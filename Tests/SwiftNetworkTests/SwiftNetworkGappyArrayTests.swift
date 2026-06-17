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

import XCTest

#if canImport(SwiftNetwork)
@testable import SwiftNetwork
#endif

@available(Network 0.1.0, *)
final class SwiftNetworkGappyArrayTests: XCTestCase {

    struct GappyElement: ~Copyable {
        let value: Int
        init(value: Int) {
            self.value = value
        }
    }

    func testAdding() throws {
        var ga = NetworkGappyArray<GappyElement>()
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)

        let first = GappyElement(value: 1)
        _ = ga.insert(first)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 1)

        let second = GappyElement(value: 2)
        _ = ga.insert(second)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 2)

        let third = GappyElement(value: 3)
        _ = ga.insert(third)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 3)
    }

    func testRemovingFromStart() throws {
        var ga = NetworkGappyArray<GappyElement>()
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)

        let first = GappyElement(value: 1)
        let firstIndex = ga.insert(first)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 1)

        let second = GappyElement(value: 2)
        let secondIndex = ga.insert(second)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 2)

        let third = GappyElement(value: 3)
        let thirdIndex = ga.insert(third)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 3)

        ga.remove(index: firstIndex)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 2)

        ga.remove(index: secondIndex)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 1)

        ga.remove(index: thirdIndex)
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)
    }

    func testRemovingFromEnd() throws {
        var ga = NetworkGappyArray<GappyElement>()
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)

        let first = GappyElement(value: 1)
        let firstIndex = ga.insert(first)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 1)

        let second = GappyElement(value: 2)
        let secondIndex = ga.insert(second)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 2)

        let third = GappyElement(value: 3)
        let thirdIndex = ga.insert(third)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 3)

        ga.remove(index: thirdIndex)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 2)

        ga.remove(index: secondIndex)
        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 1)

        ga.remove(index: firstIndex)
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)
    }

    func testRandomAddAndRemove() throws {
        var ga = NetworkGappyArray<GappyElement>()
        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)

        // Add 50 elements
        var indices = [NetworkStateIndex]()
        for i in 1...50 {
            let element = GappyElement(value: i)
            let newIndex = ga.insert(element)
            indices.append(newIndex)
        }

        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 50)

        // Remove random 25 elements
        indices.shuffle()
        for _ in 1...25 {
            let indexToRemove = indices.popLast()!
            ga.remove(index: indexToRemove)
        }

        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 25)

        // Add 75 elements
        for i in 1...75 {
            let element = GappyElement(value: i)
            let newIndex = ga.insert(element)
            indices.append(newIndex)
        }

        XCTAssertTrue(!ga.isEmpty)
        XCTAssertEqual(ga.count, 100)

        // Remove all elements in random order
        indices.shuffle()
        for index in indices {
            ga.remove(index: index)
        }

        XCTAssertTrue(ga.isEmpty)
        XCTAssertEqual(ga.count, 0)
    }
}
