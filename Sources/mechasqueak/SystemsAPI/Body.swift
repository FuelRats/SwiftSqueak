//
//  File.swift
//  
//
//  Created by Alex Sørlie Glomsaas on 09/06/2021.
//

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
        public var volcanismType: Attribute<String>
        public var atmosphereType: Attribute<String?>
        public var atmosphereComposition: Attribute<[String: Double]>
        public var solidComposition: Attribute<[String: Double]>
        public var terraformingState: Attribute<String>
        public var orbitalPeriod: Attribute<Double>
        public var semiMajorAxis: Attribute<Double>
        public var orbitalEccentricity: Attribute<Double>
        public var oribtalInclination: Attribute<Double>
        public var argOfPeriapsis: Attribute<Double>
        public var rotationalPeriod: Attribute<Double>
        public var rotationalPeriodTidallyLocked: Attribute<Double>
        public var axialTilt: Attribute<Double>
        public var rings: Attribute<[SystemsAPI.Belt]>
        public var materials: Attribute<[String: Double]>
        public var systemName: Attribute<String>
    }

    public struct Relationships: JSONAPI.Relationships {
    }
}


extension SystemsAPI {
    typealias Body = JSONEntity<BodyDescription>
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
