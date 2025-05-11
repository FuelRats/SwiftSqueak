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

typealias VectorTuple = (x: Double, y: Double, z: Double)
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices ~= index ? self[index] : nil
    }
}

struct Vector3: Codable, Equatable, AdditiveArithmetic, Numeric, Comparable,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral
{
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init?<T>(exactly source: T) where T: BinaryInteger {
        self.x = Double(source)
        self.y = Double(source)
        self.z = Double(source)
    }

    init(vector: VectorTuple) {
        let (x, y, z) = vector
        self.x = x
        self.y = y
        self.z = z
    }

    func distance(from vector: Vector3) -> Double {
        return (pow(vector.x - self.x, 2) + pow(vector.y - self.y, 2) + pow(vector.z - self.z, 2))
            .squareRoot()
    }

    static func < (lhs: Vector3, rhs: Vector3) -> Bool {
        return lhs.x < rhs.x && lhs.y < rhs.y && lhs.z < lhs.z
    }

    init(integerLiteral: IntegerLiteralType) {
        self.x = Double(integerLiteral)
        self.y = Double(integerLiteral)
        self.z = Double(integerLiteral)
    }

    init(floatLiteral: FloatLiteralType) {
        self.x = floatLiteral
        self.y = floatLiteral
        self.z = floatLiteral
    }

    typealias ArrayLiteralElement = Double
    init(arrayLiteral elements: Double...) {
        self.x = elements[safe: 0] ?? 0
        self.y = elements[safe: 1] ?? 0
        self.z = elements[safe: 2] ?? 0
    }

    static var zero: Vector3 {
        return Vector3(0, 0, 0)
    }

    var magnitude: Vector3 {
        return Vector3(abs(x), abs(y), abs(z))
    }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func += (lhs: inout Vector3, rhs: Vector3) {
        lhs.x += rhs.x
        lhs.y += rhs.y
        lhs.z += rhs.z
    }

    static func -= (lhs: inout Vector3, rhs: Vector3) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
        lhs.z -= rhs.z
    }

    static func * (lhs: Vector3, rhs: Vector3) -> Vector3 {
        return Vector3(lhs.x * rhs.x, lhs.y * rhs.y, lhs.z * rhs.z)
    }

    static func *= (lhs: inout Vector3, rhs: Vector3) {
        lhs.x *= rhs.x
        lhs.y *= rhs.y
        lhs.z *= rhs.z
    }

    func bearing(from vector: Vector3) -> Double {
        let originX = self.x - vector.x
        let originZ = self.z - vector.z
        let radians = atan2(originX, originZ)

        var degrees = radians * 180 / Double.pi
        while degrees < 0 {
            degrees += 360
        }
        return degrees
    }
}

enum CardinalDirection: String {
    case North
    case NorthEast = "North-east"
    case East
    case SouthEast = "South-east"
    case South
    case SouthWest = "South-west"
    case West
    case NorthWest = "North-west"

    init(bearing: Double) {
        switch bearing {
        case _ where bearing >= 337.5 && bearing <= 22.7:
            self = .North
        case 22.7...67.7:
            self = .NorthEast
        case 67.7...112.7:
            self = .East
        case 112.7...157.3:
            self = .SouthEast
        case 157.3...202.7:
            self = .South
        case 202.7...247.7:
            self = .SouthWest
        case 247.7...292.7:
            self = .West
        case 292.7...337.5:
            self = .NorthWest
        default:
            self = .North
        }
    }
}

extension CGPoint {
    func intersects(polygon: [CGPoint]) -> Bool {
        guard polygon.count > 0 else { return false }
        var i = 0
        var j = polygon.count - 1
        var c = false
        var vi: CGPoint
        var vj: CGPoint
        while true {
            guard i < polygon.count else { break }
            vi = polygon[i]
            vj = polygon[j]
            if (vi.y > y) != (vj.y > y) && x < (vj.x - vi.x) * (y - vi.y) / (vj.y - vi.y) + vi.x {
                c = !c
            }
            j = i
            i += 1
        }
        return c
    }
}
