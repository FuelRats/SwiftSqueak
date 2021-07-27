//
//  File.swift
//  
//
//  Created by Alex Sørlie Glomsaas on 14/06/2021.
//

import Foundation

extension Array {
    func map<T> (_ transform: @escaping (Element) async throws -> T) async rethrows -> [T] {
        var mappedElements: [T] = []
        try await withThrowingTaskGroup(of: T.self) { group in
            for element in self {
                group.async {
                    return try await transform(element)
                }
            }
            
            for try await element in group {
                mappedElements.append(element)
            }
        }
        return mappedElements
    }
    
    func compactMap<T> (_ transform: @escaping (Element) async throws -> T?) async rethrows -> [T] {
        var mappedElements: [T] = []
        try await withThrowingTaskGroup(of: T?.self) { group in
            for element in self {
                group.async {
                    return try await transform(element)
                }
            }
            
            for try await element in group {
                if let element = element {
                    mappedElements.append(element)
                }
            }
        }
        return mappedElements
    }
    
    func first (where predicate: @escaping (Element) async throws -> Bool) async rethrows -> Element? {
        for element in self {
            let result = try await predicate(element)
            if result {
                return element
            }
        }
        return nil
    }
}
