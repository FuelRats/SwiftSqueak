import Foundation
import AsyncHTTPClient

struct GithubRelease: Codable {
    let url: URL
    let id: uint64
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
        let id: uint64
        let avatarUrl: URL
        let url: URL
    }
    
    static func get() async throws -> [GithubRelease] {
        let requestUrl = URL(string: "https://api.github.com/repos/fuelrats/SwiftSqueak/releases")!

        var request = try HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try await httpClient.execute(request: request, forDecodable: [GithubRelease].self, withDecoder: decoder)
    }
}
