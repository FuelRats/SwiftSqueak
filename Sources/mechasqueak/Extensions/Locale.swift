//
//  Locale.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-04-03.
//

import Foundation

extension Locale {
    var englishDescription: String {
        let englishLocale = Locale(identifier: "en-GB")
        return englishLocale.localizedString(forIdentifier: self.identifier) ?? "unknown"
    }
}
