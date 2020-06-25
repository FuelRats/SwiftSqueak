//
//  RangeExpression.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-06-24.
//

import Foundation

protocol AnyRange {
    associatedtype Bound
    var lower: Bound? { get }
    var upper: Bound? { get }
}

extension ClosedRange: AnyRange {
    var lower: Bound? {
        return self.lowerBound
    }

    var upper: Bound? {
        return self.upperBound
    }
}

extension PartialRangeFrom: AnyRange {
    var lower: Bound? {
        return self.lowerBound
    }

    var upper: Bound? {
        return nil
    }
}

extension PartialRangeUpTo: AnyRange {
    var lower: Bound? {
        return nil
    }

    var upper: Bound? {
        return self.upperBound
    }
}

extension PartialRangeThrough: AnyRange {
    var lower: Bound? {
        return nil
    }

    var upper: Bound? {
        return self.upperBound
    }
}
