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
import JSONAPI

enum BodyDescription: ResourceObjectDescription {
    public static var jsonType: String { return "bodies" }

    public struct Attributes: JSONAPI.Attributes {
        public let bodyId: Attribute<Int64>
        public var name: Attribute<String>
        public var type: Attribute<SystemsAPI.CelestialBodyType>
        public var subType: Attribute<String>
        public var parents: Attribute<[[String: Int64]]>
        public var distanceToArrival: Attribute<Int64?>
        public var isLandable: Attribute<Bool>
        public var gravity: Attribute<Double>
        public var earthMasses: Attribute<Double>
        public var radius: Attribute<Double>
        public var surfaceTemperature: Attribute<Double>
        public var surfacePressure: Attribute<Double>
        public var volcanismType: Attribute<String?>
        public var atmosphereType: Attribute<String?>
        public var atmosphereComposition: Attribute<[String: Double]>
        public var solidComposition: Attribute<[String: Double]>
        public var terraformingState: Attribute<String>
        public var orbitalPeriod: Attribute<Double?>
        public var semiMajorAxis: Attribute<Double?>
        public var orbitalEccentricity: Attribute<Double?>
        public var oribtalInclination: Attribute<Double>?
        public var argOfPeriapsis: Attribute<Double?>
        public var rotationalPeriod: Attribute<Double?>
        public var rotationalPeriodTidallyLocked: Attribute<Bool?>
        public var axialTilt: Attribute<Double?>
        public var rings: Attribute<[SystemsAPI.Belt]>
        public var materials: Attribute<[String: Double]>
        public var systemName: Attribute<String>
    }

    public struct Relationships: JSONAPI.Relationships {
    }
}


extension SystemsAPI {
    typealias Body = SystemsAPIJSONEntity<BodyDescription>
}

extension SystemsAPI.Body {
    var description: String {
        guard let distance = self.distanceToArrival else {
            return "\(self.subType) unknown distance from main star"
        }
        let distanceString = Double(distance).eliteDistance
        return "\(self.subType) ~\(distanceString) from main star"
    }
}
