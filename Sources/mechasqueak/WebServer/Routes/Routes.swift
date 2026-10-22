//
//  Routes.swift
//  mechasqueak
//
//  Created by Alex Sørlie on 10/05/2025.
//

import Vapor
import HTMLKitVapor

struct Routes: RouteCollection {
    /// Search runs on every keystroke, so queries are capped to keep each one cheap.
    static let maxSearchLength = 100

    static func searchQuery(_ req: Request) -> String {
        return String(((try? req.query.get(String.self, at: "query")) ?? "").prefix(maxSearchLength))
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get { req in
            let releases = (try? await GithubRelease.get()) ?? []
            return try await req.htmlkit.render(MainPage(currentPage: .home, releases: releases))
        }
        
        routes.get("home") { req in
            let releases = (try? await GithubRelease.get()) ?? []
            if req.isHTMX {
                return try await req.htmlkit.render(HomePage(releases: releases))
            } else {
                return try await req.htmlkit.render(MainPage(currentPage: .home, releases: releases))
            }
        }
        
        routes.get("commands") { req in
            if req.isHTMX {
                req.htmlkit.render(CommandsPage())
            } else {
                req.htmlkit.render(MainPage(currentPage: .commands))
            }
        }
        
        routes.get("command-search") { req in
            let search = Routes.searchQuery(req)
            if search.isEmpty {
                return try await req.htmlkit.render(CommandsListView())
            }
            guard let database = mecha.sqliteDatabase else {
                throw Abort(.serviceUnavailable, reason: "Command search is not available yet")
            }
            let results = (try? await searchCommands(query: search, on: database)) ?? []
            let commands = results.compactMap({ result -> IRCBotCommandDeclaration? in
                return MechaSqueak.commands.first(where: {
                    $0.commands[0].lowercased() == result.name
                })
            })
            return try await req.htmlkit.render(CommandSearchView(commands: commands))
        }
        
        routes.get("facts") { req in
            let facts = (try? await Fact.getFactsGroupedByCategory()) ?? []
            let allFacts = Array((try? await Fact.getAllFacts()) ?? []).grouped.values.sorted(by: {
                $0.canonicalName < $1.canonicalName
            })
            
            let platformFacts = allFacts.filter({ $0.isPlatformFact }).platformGrouped
            if req.isHTMX {
                return try await req.htmlkit.render(FactsPage(factCategories: facts, platformFacts: platformFacts))
            } else {
                return try await req.htmlkit.render(MainPage(
                    currentPage: .facts,
                    factCategories: facts,
                    platformFacts: platformFacts
                ))
            }
        }
        
        routes.get("fact-message") { req in
            let name = (try? req.query.get(String.self, at: "name")) ?? ""
            let locale = (try? req.query.get(String.self, at: "locale")) ?? ""
            guard let fact = try await Fact.get(name: name, forLocale: Locale(identifier: locale)) else {
                throw Abort(.notFound)
            }
            
            return try await req.htmlkit.render(FactMessageView(fact: fact))
        }
        
        routes.get("fact-search") { req in
            let search = Routes.searchQuery(req)
            if search.isEmpty {
                let facts = (try? await Fact.getFactsGroupedByCategory()) ?? []
                let allFacts = Array((try? await Fact.getAllFacts()) ?? []).grouped.values.sorted(by: {
                    $0.canonicalName < $1.canonicalName
                })
                
                let platformFacts = allFacts.filter({ $0.isPlatformFact }).platformGrouped
                return try await req.htmlkit.render(FactListView(factCategories: facts, platformFacts: platformFacts))
            }
            
            let facts = (try? await Fact.search(search)) ?? []
            return try await req.htmlkit.render(FactSearchView(facts: facts))
        }
        
        routes.get("platform-fact") { req in
            let name = (try? req.query.get(String.self, at: "name")) ?? ""
            let locale = (try? req.query.get(String.self, at: "locale")) ?? ""
            
            let allFacts = Array((try? await Fact.getAllFacts()) ?? []).grouped.values.sorted(by: {
                $0.canonicalName < $1.canonicalName
            })
            let platformFacts = allFacts.filter({ $0.isPlatformFact }).platformGrouped
            guard let fact = platformFacts[name] else {
                throw Abort(.notFound)
            }
            
            return try await req.htmlkit.render(PlatformFactMessageGroupView(
                platformFacts: fact,
                defaultLocale: Locale(identifier: locale)
            ))
        }
    }
}

extension Request {
    var isHTMX: Bool {
        headers.first(name: "HX-Request") != nil
    }
}
