import Foundation

enum Provider: String, Decodable, CaseIterable, Sendable {
    case claude, codex

    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var shortName: String { self == .claude ? "Claude" : "Codex" }
}

struct Account: Decodable, Sendable {
    let id: String
    let authIndex: String
    let provider: String
    let email: String?
    let disabled: Bool?
    let idToken: Identity?

    struct Identity: Decodable, Sendable {
        let chatgptAccountId: String?
    }
}

struct UsageLimit: Identifiable, Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?

    var remaining: Int { Int((100 - min(100, max(0, usedPercent))).rounded()) }

    func resetText(now: Date) -> String {
        guard let resetsAt else { return "Reset not reported" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due · refresh" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 { return "Resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Resets in \(hours)h \(minutes % 60)m" }
        return "Resets in \(hours / 24)d \(hours % 24)h"
    }
}

struct AccountUsage: Identifiable, Sendable {
    let id: String
    let provider: Provider
    let name: String
    let plan: String?
    let limits: [UsageLimit]
    let error: String?

    func pinID(_ limit: UsageLimit) -> String { "\(id)/\(limit.id)" }
}

enum UsageParser {
    static func parse(_ data: Data, provider: Provider, now: Date = .now) throws -> (String?, [UsageLimit]) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        switch provider {
        case .claude:
            let usage = try decoder.decode(ClaudeUsage.self, from: data)
            var limits = usage.limits?.enumerated().compactMap { index, limit -> UsageLimit? in
                guard let percent = limit.percent else { return nil }
                let model = limit.scope?.model?.displayName
                let title = switch limit.kind {
                case "session", "five_hour": "5-hour"
                case "weekly", "weekly_all", "seven_day": "Weekly"
                case "weekly_scoped": model.map { "Weekly · \($0)" } ?? "Weekly model limit"
                default: label(limit.kind)
                }
                let id = switch limit.kind {
                case "session", "five_hour": "session"
                case "weekly", "weekly_all", "seven_day": "weekly"
                case "weekly_scoped": "scoped-\(model ?? String(index))"
                default: limit.kind
                }
                return UsageLimit(id: id, title: title, usedPercent: percent, resetsAt: date(limit.resetsAt))
            } ?? []
            for (key, title, window) in [
                ("session", "5-hour", usage.fiveHour),
                ("weekly", "Weekly", usage.sevenDay),
                ("scoped-Sonnet", "Weekly · Sonnet", usage.sevenDaySonnet),
                ("scoped-Opus", "Weekly · Opus", usage.sevenDayOpus),
                ("seven_day_oauth_apps", "Weekly · OAuth apps", usage.sevenDayOauthApps),
                ("seven_day_cowork", "Weekly · Cowork", usage.sevenDayCowork),
                ("iguana_necktie", "Other allowance", usage.iguanaNecktie)
            ] {
                guard let window, !limits.contains(where: { $0.title == title }) else { continue }
                limits.append(UsageLimit(id: key, title: title, usedPercent: window.utilization, resetsAt: date(window.resetsAt)))
            }
            if let extra = usage.extraUsage, extra.isEnabled == true,
               let used = extra.usedCredits, let total = extra.monthlyLimit, total > 0 {
                limits.append(UsageLimit(id: "extra_usage", title: "Extra usage · monthly", usedPercent: used / total * 100, resetsAt: nil))
            }
            return (nil, limits)
        case .codex:
            let usage = try decoder.decode(CodexUsage.self, from: data)
            var limits = codexWindows(usage.rateLimit, id: "usage", prefix: "", now: now)
            limits += codexWindows(usage.codeReviewRateLimit, id: "review", prefix: "Code review · ", now: now)
            for (index, extra) in (usage.additionalRateLimits ?? []).enumerated() {
                let name = extra.limitName ?? extra.meteredFeature ?? "Additional limit \(index + 1)"
                limits += codexWindows(extra.rateLimit, id: "extra-\(name)", prefix: "\(name) · ", now: now)
            }
            return (usage.planType?.capitalized, limits)
        }
    }

    private static func codexWindows(_ rate: CodexUsage.Rate?, id: String, prefix: String, now: Date) -> [UsageLimit] {
        [("primary", rate?.primaryWindow), ("secondary", rate?.secondaryWindow)].compactMap { key, window in
            guard let window, let percent = window.usedPercent else { return nil }
            let seconds = window.limitWindowSeconds
            let title: String
            switch seconds {
            case 18000: title = "5-hour"
            case 604800: title = "Weekly"
            case let duration? where (2419200...2678400).contains(duration): title = "Monthly"
            case let duration?: title = "\(duration / 3600)-hour"
            case nil: title = key == "primary" ? "5-hour" : "Weekly"
            }
            let reset = window.resetAt.map(Date.init(timeIntervalSince1970:))
                ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
            return UsageLimit(id: "\(id)-\(key)", title: prefix + title, usedPercent: percent, resetsAt: reset)
        }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    private static func label(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct ClaudeUsage: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDaySonnet: Window?
    let sevenDayOpus: Window?
    let sevenDayOauthApps: Window?
    let sevenDayCowork: Window?
    let iguanaNecktie: Window?
    let limits: [Limit]?
    let extraUsage: Extra?

    struct Window: Decodable { let utilization: Double; let resetsAt: String? }
    struct Extra: Decodable { let isEnabled: Bool?; let monthlyLimit: Double?; let usedCredits: Double? }
    struct Limit: Decodable {
        let kind: String
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
        struct Scope: Decodable {
            let model: Model?
            struct Model: Decodable { let displayName: String }
        }
    }
}

private struct CodexUsage: Decodable {
    let planType: String?
    let rateLimit: Rate?
    let codeReviewRateLimit: Rate?
    let additionalRateLimits: [Additional]?

    struct Rate: Decodable { let primaryWindow: Window?; let secondaryWindow: Window? }
    struct Window: Decodable {
        let usedPercent: Double?
        let resetAt: Double?
        let resetAfterSeconds: Double?
        let limitWindowSeconds: Int?
    }
    struct Additional: Decodable { let limitName: String?; let meteredFeature: String?; let rateLimit: Rate? }
}
