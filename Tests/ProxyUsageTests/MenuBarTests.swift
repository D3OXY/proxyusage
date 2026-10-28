import AppKit
import Testing
@testable import ProxyUsage

private let claude = AccountUsage(id: "claude", provider: .claude, name: "personal@example.com", plan: nil, limits: [
    UsageLimit(id: "session", title: "5-hour", usedPercent: 40, resetsAt: nil),
    UsageLimit(id: "weekly", title: "Weekly", usedPercent: 10, resetsAt: nil)
], error: nil)
private let codex = AccountUsage(id: "codex", provider: .codex, name: "personal@example.com", plan: "Pro", limits: [
    UsageLimit(id: "session", title: "5-hour", usedPercent: 25, resetsAt: nil),
    UsageLimit(id: "weekly", title: "Weekly", usedPercent: 50, resetsAt: nil)
], error: nil)

@Test @MainActor func fourPinnedLimitsFitIn60Points() throws {
    let pins = [claude, codex].flatMap { account in
        account.limits.map { PinnedLimit(id: account.pinID($0), label: "\(account.provider.shortName) \($0.title)") }
    }
    let content = MenuBarContent(pins: pins, accounts: [claude, codex], unavailable: false)
    #expect(content.summary.contains("Claude 5-hour: 40% used"))
    #expect(content.groups.count == 2)
    #expect(content.groups.map { $0.metrics.count } == [2, 2])
    #expect(content.groups.flatMap(\.metrics).map(\.value) == ["40%", "10%", "25%", "50%"])
    let image = try #require(MenuBarRenderer.image(for: content))
    #expect(image.size.width <= 60)
    #expect(image.size == NSSize(width: content.width, height: 18))
    #expect(image.isTemplate)
    #expect(image.accessibilityDescription == content.summary)
}

@Test func unreadableAccountsKeepTheirPinnedPlaceWithADash() {
    let pins = [PinnedLimit(id: "claude/session", label: "Claude 5h"), PinnedLimit(id: "codex/weekly", label: "Codex Weekly")]
    let content = MenuBarContent(pins: pins, accounts: [], unavailable: true)
    #expect(content.groups.map(\.provider) == [.claude, .codex])
    #expect(content.groups.flatMap(\.metrics).map(\.value) == ["—", "—"])
}

@Test(arguments: [false, true]) @MainActor func weeklyOnlyPinLeavesTheSessionColumnEmpty(unavailable: Bool) throws {
    let claudePins = claude.limits.map { PinnedLimit(id: claude.pinID($0), label: "Claude \($0.title)") }
    var images: [Data] = []
    for title in ["5-hour", "Weekly"] {
        let account = AccountUsage(id: "codex", provider: .codex, name: "test", plan: nil, limits: [
            UsageLimit(id: "limit", title: title, usedPercent: 0, resetsAt: nil)
        ], error: nil)
        let pins = claudePins + [PinnedLimit(id: "codex/limit", label: "Codex \(title)")]
        let content = MenuBarContent(pins: pins, accounts: unavailable ? [] : [claude, account], unavailable: unavailable)
        let value = unavailable ? "—" : "0%"
        #expect(content.alignedMetrics[1].map { $0?.value } == (title == "Weekly" ? [nil, value] : [value, nil]))
        let image = try #require(MenuBarRenderer.image(for: content))
        images.append(try #require(image.tiffRepresentation))
    }
    #expect(images[0] != images[1])
}

@Test @MainActor func sharedColumnsFitFullUsageAndKeepRepeatedWindows() {
    let second = AccountUsage(id: "second", provider: .claude, name: "second", plan: nil, limits: claude.limits, error: nil)
    let full = AccountUsage(id: "codex", provider: .codex, name: "test", plan: nil, limits: [
        UsageLimit(id: "weekly", title: "Weekly", usedPercent: 100, resetsAt: nil)
    ], error: nil)
    let accounts = [claude, second, full]
    let pins = accounts.flatMap { account in
        account.limits.map { PinnedLimit(id: account.pinID($0), label: "\(account.provider.shortName) \($0.title)") }
    }
    let content = MenuBarContent(pins: pins, accounts: accounts, unavailable: false)
    #expect(content.alignedMetrics[0].compactMap { $0?.value } == ["40%", "10%", "40%", "10%"])
    #expect(content.alignedMetrics[1].map { $0?.value } == [nil, "100%", nil, nil])
    #expect(content.columnWidths[1] >= ceil(("100%" as NSString).size(withAttributes: [.font: content.groups[1].font(rows: 1)]).width))
}

@Test @MainActor func percentageColumnsStaySteadyBelow100() {
    for count in [1, 2] {
        let groups = [nil, 0, 9, 10, 99].map { used in
            MenuBarContent.Group(provider: .claude, metrics: Array(repeating: .init(label: "Claude 5h", used: used, window: "5h"), count: count))
        }
        for rows in [1, 2] {
            #expect(Set(groups.map { $0.columnWidths(rows: rows) }).count == 1)
        }
    }
}

@Test @MainActor func fullUsageFitsWithoutWideningOtherColumns() {
    let group = MenuBarContent.Group(provider: .claude, metrics: [0, 99, 100, nil, 9].map {
        .init(label: "Claude limit", used: $0, window: "limit")
    })
    let widths = group.columnWidths(rows: 2)
    #expect(widths.count == 3)
    #expect(widths[0] == widths[2])
    #expect(widths[1] > widths[0])
    for (index, metric) in group.metrics.enumerated() {
        let textWidth = (metric.value as NSString).size(withAttributes: [.font: group.font(rows: 2)]).width
        #expect(widths[index / 2] >= ceil(textWidth))
    }
    let rowWidths = group.columnWidths(rows: 1)
    for (index, metric) in group.metrics.enumerated() {
        let textWidth = (metric.value as NSString).size(withAttributes: [.font: group.font(rows: 1)]).width
        #expect(rowWidths[index] >= ceil(textWidth))
    }
}
