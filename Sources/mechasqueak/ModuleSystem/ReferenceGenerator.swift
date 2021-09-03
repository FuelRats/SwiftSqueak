//
//  ReferenceGenerator.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 16/03/2021.
//

import Foundation

struct ReferenceGenerator {
    static func generate (inPath path: URL) {
        let html = HelpCategory.allCases.map({ $0.html }).joined()
        try! html.write(to: path.appendingPathComponent("commandref.html"), atomically: true, encoding: .utf8)
    }
}

protocol HTMLRepresentable {
    var html: String { get }
}

extension HelpCategory: HTMLRepresentable {
    var html: String {
        let categoryDescription = lingo.localize("help.category.\(self)", locale: "en-GB")
        let commands = MechaSqueak.commands.filter({
            $0.category == self
        })
        let commandsHtml = commands.map({ $0.html }).joined()
        return """
            <h2>
              <span style="color: rgb(0,0,0);">\(self.rawValue.firstCapitalized)</span>
            </h2>
            <p>
              <strong>
                <span style="color: rgb(0,0,0);">
                  <span style="text-decoration: none;">\(categoryDescription)</span>
                </span>
              </strong>
            </p>
            \(commandsHtml)
            <br/>
        """
    }
}

extension IRCBotCommandDeclaration: HTMLRepresentable {
    var html: String {
        var html = """
        <h3>
        <span style="color: rgb(0,0,0);text-decoration: none;">
            <span style="text-decoration: none;">!\(self.commands.first!) <span style="color: rgb(122,134,154);">
        """
        
        if self.options.count > 0 {
            html += "<em>[-\(String(self.options))] </em>"
        }
        
        for option in self.namedOptions {
            html += "<em>[--\(option)] </em>"
        }
        html += "</span>"
        for case .param(let name, _, let type, let nullability) in parameters {
            switch type {
            case .standard:
                if nullability == .required {
                    html += "&lt;\(name)&gt; "
                } else {
                    html += """
                        <span style="color: rgb(122,134,154);">
                            <em>[\(name)]</em>
                        </span>
                        """
                }
                
            case .multiple:
                if nullability == .required {
                    for index in 1...3 {
                        html += "&lt;\(name) \(index)&gt; "
                    }
                } else {
                    html += "<span style=\"color: rgb(122,134,154);\">"
                    for index in 1...3 {
                        html += "<em>[\(name) \(index)]</em> "
                    }
                    html += "</span>"
                }
                
            case .continuous:
                if nullability == .required {
                    html += "&lt;\(name)...&gt; "
                } else {
                    html += """
                        <span style="color: rgb(122,134,154);">
                            <em>[\(name)...]</em>
                        </span>
                        """
                }
            }
        }
        
        html += "</span></span></h3>"
        
        if self.commands.count > 1 {
            let aliases = self.commands.dropFirst().map({ "!\($0)" }).joined(separator: " ")
            html += """
                <p>
                  <span style="color: rgb(0,0,0);text-decoration: none;">
                    <span style="text-decoration: none;">
                      <strong>Aliases</strong>: \(aliases)
                    </span>
                  </span>
                </p>
            """
        }
        
        let permissionGroups = self.permission?.groups
            .sorted(by: { $0.priority < $1.priority })
            .map({ $0.groupDescription }) ?? []
        
        if permissionGroups.count > 0 {
            html += """
                <p>
                  <span style="color: rgb(0,0,0);text-decoration: none;">
                    <span style="text-decoration: none;">
                      <strong>Permissions</strong>: \(permissionGroups.joined(separator: ", "))
                    </span>
                  </span>
                </p>
            """
        }
        
        html += """
            <p style="margin-left: 30.0px;">
              <span style="color: rgb(0,0,0);text-decoration: none;">\(self.description)</span>
            </p>
        """
        let commandIdentifier = "help.command.\(self.commands[0])"
        let fullDescription = lingo.localize(commandIdentifier, locale: "en-GB")
        if fullDescription != commandIdentifier {
            html += """
            <p style="margin-left: 30.0px;">
              <span style="color: rgb(0,0,0);text-decoration: none;">\(fullDescription)</span>
            </p>
            """
        }
        
        if self.options.count > 0 || self.namedOptions.count > 0 {
            html += """
                <p style="margin-left: 30.0px;">
                  <span style="color: rgb(0,0,0);text-decoration: none;">Options:</span>
                </p>
            """
            
            for option in options {
                let optionDescription = lingo.localize("help.command.\(self.commands[0]).\(option)", locale: "en-GB")
                html += """
                    <p style="margin-left: 60.0px;">
                      <span style="color: rgb(0,0,0);text-decoration: none;"><strong>-\(option)</strong> \(optionDescription)</span>
                    </p>
                """
            }
            
            for option in namedOptions {
                let optionDescription = lingo.localize("help.command.\(self.commands[0]).\(option)", locale: "en-GB")
                html += """
                    <p style="margin-left: 60.0px;">
                      <span style="color: rgb(0,0,0);text-decoration: none;"><strong>--\(option)</strong> \(optionDescription)</span>
                    </p>
                """
            }
        }
        
        html += """
            <p style="margin-left: 30.0px;">
              <span style="color: rgb(0,0,0);">
                <span style="text-decoration: none;">
                  <span style="color: rgb(0,0,0);text-decoration: none;">Example:</span>
                </span>
              </span>
            </p>
            <p style="margin-left: 60.0px;">
              <span style="color: rgb(0,0,0);">
                <span style="text-decoration: none;">
                  <span style="color: rgb(0,0,0);text-decoration: none;">!\(commands[0]) \(example)</span>
                </span>
              </span>
            </p>
              <br/>
        """
        return html
    }
}
