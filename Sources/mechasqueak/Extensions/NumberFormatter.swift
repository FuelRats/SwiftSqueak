//
//  NumberFormatter.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-03-31.
//

import Foundation

extension NumberFormatter {
    static func englishFormatter () -> NumberFormatter {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSize = 3
        numberFormatter.maximumFractionDigits = 1
        numberFormatter.roundingMode = .halfUp
        return numberFormatter
    }

    func string (from number: Int) -> String? {
        return self.string(from: NSNumber(value: number))
    }

    func string (from number: Int64) -> String? {
        return self.string(from: NSNumber(value: number))
    }

    func string (from number: Double) -> String? {
        return self.string(from: NSNumber(value: number))
    }
}
