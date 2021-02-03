/*
 Copyright 2021 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

extension NumberFormatter {
    static func englishFormatter () -> NumberFormatter {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.thousandSeparator = ","
        numberFormatter.decimalSeparator = "."
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

extension Int {
    var isEven: Bool {
        return self % 2 == 0
    }
}

extension Double {
    var clean: String {
       return String(format: "%.0f", floor(self))
    }
    
    var eliteDistance: String {
        let formatter = NumberFormatter.englishFormatter()
        formatter.maximumFractionDigits = 2
        
        let lightYears = self / 60/60/24/365
        var formattedDistance = (formatter.string(from: self) ?? "\(self)") + "ls"
        let scientificFormatter = NumberFormatter()
        scientificFormatter.numberStyle = .scientific
        scientificFormatter.positiveFormat = "0.###E+0"
        scientificFormatter.exponentSymbol = "E"

        if self > 3.1*pow(10, 13) {
            formattedDistance = "\(scientificFormatter.string(from: lightYears) ?? "\(lightYears)")ly"
        } else if self > 3.6*pow(10, 6) {
            formattedDistance = (formatter.string(from: lightYears)  ?? "\(lightYears)") + "ly"
        } else if self < 1 {
            formattedDistance = "\(scientificFormatter.string(from: self) ?? "\(self)")ls"
        }
        return formattedDistance
    }
}
