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
    subscript (safe index: Int) -> Element? {
        return indices ~= index ? self[index] : nil
    }
}

struct Vector3: Codable, Equatable, AdditiveArithmetic, Numeric, Comparable, ExpressibleByFloatLiteral, ExpressibleByArrayLiteral {
    var x: Double
    var y: Double
    var z: Double
    
    init (_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    init?<T>(exactly source: T) where T : BinaryInteger {
        self.x = Double(source)
        self.y = Double(source)
        self.z = Double(source)
    }
    
    init (vector: VectorTuple) {
        let (x, y, z) = vector
        self.x = x
        self.y = y
        self.z = z
    }
    
    static func < (lhs: Vector3, rhs: Vector3) -> Bool {
        return lhs.x < rhs.x && lhs.y < rhs.y && lhs.z < lhs.z
    }
    
    init (integerLiteral: IntegerLiteralType) {
        self.x = Double(integerLiteral)
        self.y = Double(integerLiteral)
        self.z = Double(integerLiteral)
    }
    
    init (floatLiteral: FloatLiteralType) {
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
}
