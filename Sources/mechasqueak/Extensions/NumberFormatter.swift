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
        
        let lightYears = self / 60/60/24/365.25
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
    
    func timeSpan (components: [TimeUnit] = [.year, .day, .hour, .minute, .second], maximumUnits: UInt? = nil) -> String {
        var value = self
        let components = components.sorted(by: { $0.rawValue > $1.rawValue })
        var values: [TimeUnit: Double] = [:]
        for component in components {
            let compResult = floor(value / component.rawValue)
            if compResult > 0 {
                values[component] = compResult
                value = value.truncatingRemainder(dividingBy: component.rawValue)
            }
        }
        
        let formatter = NumberFormatter.englishFormatter()
        formatter.maximumFractionDigits = 0
        
        var result = ""
        var index = 0
        for (_, item) in values.enumerated().sorted(by: { $0.element.key.rawValue > $1.element.key.rawValue }) {
            let (unit, value) = item
            if let maximumUnits = maximumUnits, index >= maximumUnits {
                break
            }
            
            let description = value == 1 ? String(describing: unit) : "\(String(describing: unit))s"
            if index != 0 && (index + 1 == values.count || index + 1 >= (maximumUnits ?? .max)) {
                result += ", and "
            } else if index != 0 {
                result += ", "
            }
            result += "\(formatter.string(from: value)!) \(description)"
            index += 1
        }
        return result
    }
    
    func distanceToSeconds (destinationGravity: Bool = false) -> Double {
        var distance = self
        if destinationGravity {
            distance = distance / 2
        }
        
        var seconds = 0.0
        if distance < 100000 {
            seconds = 8.9034 * pow(distance, 0.3292)
        } else if distance < 1907087 {
            // -8*(10 ** -23) * (x ** 4) + 4*(10 ** -16) * (x ** 3) - 8*(10 ** -10) * (x ** 2) + 0.0014 * x + 264.79
            let part1 = -8 * pow(10, -23) * pow(distance, 4)
            let part2 = 4 * pow(10, -16) * pow(distance, 3) - 8 * pow(10, -10) * pow(distance, 2)
            let part3 = 0.0014 * distance + 264.79
            seconds = part1 + part2 + part3
        } else {
            seconds = (distance - 5265389.609) / 2001 + 3412
        }
        
        if seconds < 0 {
            return 0
        }

        if destinationGravity {
            seconds = seconds * 2
        }
        return seconds
    }
    
    func distanceToSecondsOld (destinationGravity: Bool = false) -> Double {
        var distance = self
        if destinationGravity {
            distance = distance / 2
        }

        var seconds = 0.0
        if distance < 448865 {
            seconds = 4.4708*pow(distance, 0.3899)
        } else if distance > 4300000 {
            seconds = (distance - 5100000.0) / 2001 + 3420
        }
        else {
            /*
                Thank you to RadLock for creating the original equation.
             */
           let part1 = 33.7+1.87*pow(10 as Double, -3)*Double(distance)
           let part2 = -8.86*pow(10 as Double, -10) * pow(Double(distance), 2)
           let part3 = 2.37*pow(10 as Double, -16) * pow(Double(distance), 3)
           let part4 = -2.21*pow(10 as Double, -23) * pow(Double(distance), 4)
           seconds = part1 + part2 + part3 + part4
        }

        if seconds < 0 {
            return 0
        }

        if destinationGravity {
            seconds = seconds * 2
        }
        return seconds
    }
}

enum TimeUnit: Double {
    case year = 31557600.0
    case month = 2592000.0
    case day = 86400.0
    case hour = 3600.0
    case minute = 60.0
    case second = 1.0
}
