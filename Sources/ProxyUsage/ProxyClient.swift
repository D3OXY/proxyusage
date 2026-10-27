import Foundation

struct ProxyClient: Sendable {
    let baseURL: URL
    let key: String
    var session: URLSession = .shared

    static func baseURL(from input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased()),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else {
            throw ProxyError.message("Enter the proxy's full http:// or https:// URL.")
        }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/management.html", "/v0/management", "/v1"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        parts.path = path
        guard let url = parts.url else { throw ProxyError.message("The proxy URL is invalid.") }
        return url
    }

    func accounts() async throws -> [Account] {
        struct Response: Decodable { let files: [Account] }
        return try await management("auth-files", body: nil, as: Response.self).files
            .filter { Provider(rawValue: $0.provider) != nil && $0.disabled != true }
    }

    func usage(for account: Account) async -> AccountUsage {
        let provider = Provider(rawValue: account.provider)!
        let name = account.email ?? account.id
        do {
            let data = try await providerData(for: account, provider: provider)
            let (plan, limits) = try UsageParser.parse(data, provider: provider)
            return AccountUsage(id: account.id, provider: provider, name: name, plan: plan, limits: limits,
                                error: limits.isEmpty ? "No usage limits reported by this account." : nil)
        } catch {
            return AccountUsage(id: account.id, provider: provider, name: name, plan: nil, limits: [],
                                error: Self.message(for: error))
        }
    }

    func providerData(for account: Account, provider: Provider) async throws -> Data {
        var headers = ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json"]
        let url: String
        if provider == .claude {
            url = "https://api.anthropic.com/api/oauth/usage"
            headers["anthropic-beta"] = "oauth-2025-04-20"
            headers["User-Agent"] = "claude-code/2.1.273"
        } else {
            url = "https://chatgpt.com/backend-api/wham/usage"
            headers["OpenAI-Beta"] = "codex-1"
            headers["Originator"] = "Codex Desktop"
            headers["Chatgpt-Account-Id"] = account.idToken?.chatgptAccountId
        }
        let body = APICall(authIndex: account.authIndex, method: "GET", url: url, header: headers)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let response = try await management("api-call", body: encoder.encode(body), as: APIResponse.self)
        guard (200..<300).contains(response.statusCode) else {
            throw ProxyError.message("\(provider.title) returned HTTP \(response.statusCode). Try refreshing later.")
        }
        return Data(response.body.utf8)
    }

    private func management<T: Decodable>(_ path: String, body: Data?, as type: T.Type) async throws -> T {
        let url = baseURL.appendingPathComponent("v0/management/\(path)")
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProxyError.message("The proxy returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            if [401, 403].contains(http.statusCode) {
                throw ProxyError.message("Management access denied. Check the management key in Settings.")
            }
            throw ProxyError.message("The proxy returned HTTP \(http.statusCode).")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    static func message(for error: Error) -> String {
        if let error = error as? ProxyError { return error.localizedDescription }
        if error is DecodingError { return "The proxy returned usage data this app couldn't read." }
        return "Couldn't reach the proxy. Check the URL and your network connection."
    }
}

enum ProxyError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

private struct APICall: Encodable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
}

private struct APIResponse: Decodable {
    let statusCode: Int
    let body: String
}
