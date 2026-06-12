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

// Availability due to `BasicContainers`'s `UniqueArray`
@available(anyAppleOS 26, *)
typealias NetworkUniqueArray = BasicContainers.UniqueArray
// Availability due to `BasicContainers`'s `RigidArray`
@available(anyAppleOS 26, *)
typealias NetworkRigidArray = BasicContainers.RigidArray

// Availability due to `DequeModule`'s `UniqueDeque`
@available(anyAppleOS 26, *)
typealias NetworkUniqueDeque = DequeModule.UniqueDeque

#endif
