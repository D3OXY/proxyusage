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

@Test @MainActor func fourPinnedLimitsFitIn108Points() throws {
    let pins = [claude, codex].flatMap { account in
        account.limits.map { PinnedLimit(id: account.pinID($0), label: "\(account.provider.shortName) \($0.title)") }
    }
    let content = MenuBarContent(pins: pins, accounts: [claude, codex], unavailable: false)
    #expect(content.groups.count == 2)
    #expect(content.groups.map { $0.metrics.count } == [2, 2])
    #expect(content.groups.flatMap(\.metrics).map(\.value) == ["60%", "90%", "75%", "50%"])
    let image = try #require(MenuBarRenderer.image(for: content))
    #expect(image.size == NSSize(width: 108, height: 18))
    #expect(image.isTemplate)
}

@Test func unreadableAccountsKeepTheirPinnedPlaceWithADash() {
    let pins = [PinnedLimit(id: "claude/session", label: "Claude 5h"), PinnedLimit(id: "codex/weekly", label: "Codex Weekly")]
    let content = MenuBarContent(pins: pins, accounts: [], unavailable: true)
    #expect(content.groups.map(\.provider) == [.claude, .codex])
    #expect(content.groups.flatMap(\.metrics).map(\.value) == ["—", "—"])
}

@Test func secondPinUsesTheSameWidthAsOnePin() {
    let first = PinnedLimit(id: "claude/session", label: "Claude 5h")
    let second = PinnedLimit(id: "claude/weekly", label: "Claude Weekly")
    let one = MenuBarContent(pins: [first], accounts: [claude], unavailable: false)
    let two = MenuBarContent(pins: [first, second], accounts: [claude], unavailable: false)
    #expect(one.width == two.width)
}
