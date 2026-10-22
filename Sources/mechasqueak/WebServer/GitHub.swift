import Foundation
import AsyncHTTPClient

struct GithubRelease: Codable {
    let url: URL
    let id: UInt64
    let tagName: String
    let author: Author
    let name: String
    let draft: Bool
    let prerelease: Bool
    let createdAt: Date
    let publishedAt: Date?
    let body: String
    
    struct Author: Codable {
        let login: String
        let id: UInt64
        let avatarUrl: URL
        let url: URL
    }
    
    /// Every page view would otherwise call GitHub, whose unauthenticated limit is 60 requests an hour.
    static let cacheLifetime: TimeInterval = 600
    private static let cache = Locked<(fetchedAt: Date, releases: [GithubRelease])?>(nil)

    static func get() async throws -> [GithubRelease] {
        if let cached = cache.current, Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime {
            return cached.releases
        }
        do {
            let releases = try await fetch()
            cache.withValue({ $0 = (fetchedAt: Date(), releases: releases) })
            return releases
        } catch {
            if let stale = cache.current {
                return stale.releases
            }
            throw error
        }
    }

    private static func fetch() async throws -> [GithubRelease] {
        let requestUrl = URL(string: "https://api.github.com/repos/fuelrats/SwiftSqueak/releases")!

        var request = try HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try await httpClient.execute(request: request, forDecodable: [GithubRelease].self, withDecoder: decoder)
    }
}
