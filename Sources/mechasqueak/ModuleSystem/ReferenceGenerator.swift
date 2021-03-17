//
//  ReferenceGenerator.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 16/03/2021.
//

import Foundation

struct ReferenceGenerator {
    static func generate () {
        
    }
}

protocol HTMLRepresentable {
    var html: String { get }
}

extension IRCBotCommandDeclaration: HTMLRepresentable {
    var html: String {
        var html = """
        <span style="color: rgb(0,0,0);text-decoration: none;">
            <span style="text-decoration: none;">\(self.commands.first!) <span style="color: rgb(122,134,154);">
        """
        
        if self.options.count > 0 {
            html += "<em>[-\(self.options)] </em>"
        }
        
        for option in self.namedOptions {
            html += "<em>[--\(option)] </em>"
        }
        html += "</span>"
        
        html += "</span></span>"
        return html
    }
}
