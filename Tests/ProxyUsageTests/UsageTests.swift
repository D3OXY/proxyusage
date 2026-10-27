import Foundation
import Testing
@testable import ProxyUsage

@Test func claudeIncludesSessionWeeklyAndScopedLimitsWithoutDuplicates() throws {
    let data = Data(#"""
    {
      "five_hour":{"utilization":21,"resets_at":"2030-01-01T12:00:00Z"},
      "seven_day":{"utilization":43,"resets_at":null},
      "seven_day_sonnet":{"utilization":12,"resets_at":null},
      "limits":[
        {"kind":"session","percent":21,"resets_at":"2030-01-01T12:00:00.123Z"},
        {"kind":"weekly_all","percent":43,"resets_at":null},
        {"kind":"weekly_scoped","percent":5,"scope":{"model":{"display_name":"Opus"}}}
      ],
      "extra_usage":{"is_enabled":true,"monthly_limit":1000,"used_credits":250}
    }
    """#.utf8)
    let (_, limits) = try UsageParser.parse(data, provider: .claude)
    #expect(limits.map(\.title) == ["5-hour", "Weekly", "Weekly · Opus", "Weekly · Sonnet", "Extra usage · monthly"])
    #expect(limits.map(\.remaining) == [79, 57, 95, 88, 75])
    #expect(limits[0].resetsAt != nil)
}

@Test func codexIncludesMonthlyReviewAndAdditionalLimits() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let data = Data(#"""
    {
      "plan_type":"pro",
      "rate_limit":{
        "primary_window":{"used_percent":24,"reset_at":2000,"limit_window_seconds":18000},
        "secondary_window":{"used_percent":80,"reset_after_seconds":600,"limit_window_seconds":2592000}
      },
      "code_review_rate_limit":{"secondary_window":{"used_percent":5,"limit_window_seconds":604800}},
      "additional_rate_limits":[{"limit_name":"GPT","rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000}}}]
    }
    """#.utf8)
    let (plan, limits) = try UsageParser.parse(data, provider: .codex, now: now)
    #expect(plan == "Pro")
    #expect(limits.map(\.title) == ["5-hour", "Monthly", "Code review · Weekly", "GPT · 5-hour"])
    #expect(limits.map(\.remaining) == [76, 20, 95, 0])
    #expect(limits[1].resetsAt == now.addingTimeInterval(600))
}

@Test func missingWindowsStayMissingAndPercentagesAreClamped() throws {
    let (_, limits) = try UsageParser.parse(Data(#"{"rate_limit":null}"#.utf8), provider: .codex)
    #expect(limits.isEmpty)
    #expect(UsageLimit(id: "a", title: "a", usedPercent: 101, resetsAt: nil).remaining == 0)
    #expect(UsageLimit(id: "a", title: "a", usedPercent: -5, resetsAt: nil).remaining == 100)
    let now = Date.now
    #expect(UsageLimit(id: "a", title: "a", usedPercent: 90, resetsAt: now.addingTimeInterval(-1)).resetText(now: now) == "Reset due · refresh")
}

@Test func proxyURLAcceptsDashboardLinksAndRejectsCredentials() throws {
    #expect(try ProxyClient.baseURL(from: " https://proxy.ts.net/management.html#/quota ").absoluteString == "https://proxy.ts.net")
    #expect(try ProxyClient.baseURL(from: "http://localhost:8317/v0/management/").absoluteString == "http://localhost:8317")
    #expect(throws: ProxyError.self) { try ProxyClient.baseURL(from: "file:///tmp/proxy") }
    #expect(throws: ProxyError.self) { try ProxyClient.baseURL(from: "https://user:secret@proxy.test") }
}

@Test func clientUsesManagementAPIWithoutSendingTheKeyToTheProvider() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    let client = ProxyClient(baseURL: URL(string: "https://proxy.test")!, key: "test-management-key", session: URLSession(configuration: config))
    let accounts = try await client.accounts()
    #expect(accounts.count == 2)
    let claude = await client.usage(for: accounts[0])
    let codex = await client.usage(for: accounts[1])
    #expect(claude.error == nil)
    #expect(claude.limits.first?.remaining == 70)
    #expect(codex.error == nil)
    #expect(codex.limits.first?.remaining == 80)
}

@Test func providerFailureStaysOnItsAccount() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    let client = ProxyClient(baseURL: URL(string: "https://proxy.test")!, key: "test-management-key", session: URLSession(configuration: config))
    let account = Account(id: "failed", authIndex: "fail", provider: "claude", email: nil, disabled: false, idToken: nil)
    let result = await client.usage(for: account)
    #expect(result.limits.isEmpty)
    #expect(result.error?.contains("HTTP 429") == true)
    #expect(result.error?.contains("private response") == false)
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            #expect(request.url?.host == "proxy.test")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-management-key")
            let responseData: Data
            if request.url?.path == "/v0/management/auth-files" {
                #expect(request.httpMethod == "GET")
                responseData = Data(#"""
                {"files":[
                  {"id":"claude","auth_index":"a","provider":"claude"},
                  {"id":"codex","auth_index":"b","provider":"codex","id_token":{"chatgpt_account_id":"workspace"}},
                  {"id":"off","auth_index":"c","provider":"claude","disabled":true},
                  {"id":"other","auth_index":"d","provider":"other"}
                ]}
                """#.utf8)
            } else {
                #expect(request.url?.path == "/v0/management/api-call")
                #expect(request.httpMethod == "POST")
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        data.append(buffer, count: count)
                    }
                }
                let body = try JSONDecoder().decode(Call.self, from: data)
                #expect(body.method == "GET")
                #expect(body.header["Authorization"] == "Bearer $TOKEN$")
                let payload: String
                let status: Int
                if body.auth_index == "fail" {
                    status = 429
                    payload = "private response"
                } else if body.auth_index == "a" {
                    #expect(body.url == "https://api.anthropic.com/api/oauth/usage")
                    #expect(body.header["anthropic-beta"] == "oauth-2025-04-20")
                    #expect(body.header["User-Agent"]?.hasPrefix("claude-code/") == true)
                    payload = #"{"five_hour":{"utilization":30,"resets_at":null}}"#
                    status = 200
                } else {
                    #expect(body.url == "https://chatgpt.com/backend-api/wham/usage")
                    #expect(body.header["Chatgpt-Account-Id"] == "workspace")
                    payload = #"{"rate_limit":{"primary_window":{"used_percent":20}}}"#
                    status = 200
                }
                responseData = try JSONSerialization.data(withJSONObject: ["status_code": status, "body": payload])
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseData)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private struct Call: Decodable {
        let auth_index: String
        let method: String
        let url: String
        let header: [String: String]
    }
}
