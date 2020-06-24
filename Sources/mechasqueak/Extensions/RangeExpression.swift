//
//  RangeExpression.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-06-24.
//

import Foundation

protocol EvaluableRange {
    associatedtype Bound
    var lower: Bound? { get }
    var upper: Bound? { get }
}

extension ClosedRange: EvaluableRange {
    var lower: Bound? {
        return self.lowerBound
    }

    var upper: Bound? {
        return self.upperBound
    }
}

extension PartialRangeFrom: EvaluableRange {
    var lower: Bound? {
        return self.lowerBound
    }

    var upper: Bound? {
        return nil
    }
}

extension PartialRangeUpTo: EvaluableRange {
    var lower: Bound? {
        return nil
    }

    var upper: Bound? {
        return self.upperBound
    }
}

extension PartialRangeThrough: EvaluableRange {
    var lower: Bound? {
        return nil
    }

    var upper: Bound? {
        return self.upperBound
    }
}
