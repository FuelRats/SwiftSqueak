//
//  WebServer.swift
//  mechasqueak
//
//  Created by Alex Sørlie on 10/05/2025.
//

import Vapor

final class WebServer {
    private let app: Application

    init(configuration: WebServerConfiguration) async throws {
        #if DEBUG
        let envName = "development"
        #else
        let envName = "production"
        #endif

        let env = Environment(name: envName, arguments: ["vapor"])
        self.app = try await Application.make(env)
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
        print("Serving static files from: \(app.directory.publicDirectory)")
        
        self.app.http.server.configuration.hostname = configuration.host
        self.app.http.server.configuration.port = configuration.port
        try app.register(collection: Routes())
    }

    func start() async throws {
        try await app.startup()
    }

    func stop() {
        app.shutdown()
    }

    func wait() async throws {
        try await app.running?.onStop.get()
    }
}
