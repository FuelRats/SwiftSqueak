//
//  File.swift
//  
//
//  Created by Alex Sørlie Glomsaas on 09/06/2021.
//

import Foundation
import JSONAPI

enum StationDescription: ResourceObjectDescription {
    public static var jsonType: String { return "stations" }

    public struct Attributes: JSONAPI.Attributes {
        public var marketId: Attribute<Int64>
        public var type: Attribute<SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.StationType>
        public var name: Attribute<String>
        public var distanceToArrival: Attribute<Double>
        public var allegiance: Attribute<String>
        public var government: Attribute<String>
        public var economy: Attribute<String>
        public var haveMarket: Attribute<Bool>
        public var haveShipyard: Attribute<Bool>
        public var haveOutfitting: Attribute<Bool>
        public var otherServices: Attribute<String>
        public var systemName: Attribute<String>
    }

    public struct Relationships: JSONAPI.Relationships {
    }
}

extension SystemsAPI {
    typealias Station = JSONEntity<StationDescription>
}
