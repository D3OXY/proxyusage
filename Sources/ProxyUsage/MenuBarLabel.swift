import AppKit

struct MenuBarContent: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        let label: String
        let used: Int?
        var value: String { used.map { "\($0)%" } ?? "—" }
    }

    struct Group: Equatable, Sendable {
        let provider: Provider
        let metrics: [Metric]
        var width: CGFloat { 20 + CGFloat((metrics.count + 1) / 2) * 30 }
    }

    let groups: [Group]
    var width: CGFloat { groups.reduce(0) { $0 + $1.width } + CGFloat(max(0, groups.count - 1)) * 8 }
    var summary: String {
        groups.flatMap(\.metrics).map { "\($0.label): \($0.value) used" }.joined(separator: "\n")
    }

    init(pins: [PinnedLimit], accounts: [AccountUsage], unavailable: Bool) {
        groups = Provider.allCases.compactMap { provider in
            let metrics = pins.compactMap { pin -> Metric? in
                let account = accounts.first { pin.id.hasPrefix("\($0.id)/") }
                let source = account?.provider ?? Provider.allCases.first { pin.label.hasPrefix($0.shortName) }
                guard source == provider else { return nil }
                let limit = account?.limits.first { account?.pinID($0) == pin.id }
                return Metric(label: pin.label, used: unavailable ? nil : limit?.used)
            }
            return metrics.isEmpty ? nil : Group(provider: provider, metrics: metrics)
        }
    }
}

// OpenUsage's text strip groups bare values beside one provider mark, with pairs stacked vertically.
@MainActor enum MenuBarRenderer {
    private static var cached: (MenuBarContent, NSImage)?

    static func image(for content: MenuBarContent) -> NSImage? {
        guard !content.groups.isEmpty else { return nil }
        if let cached, cached.0 == content { return cached.1 }
        let image = NSImage(size: NSSize(width: content.width, height: 18))
        image.lockFocus()
        var x: CGFloat = 0
        for group in content.groups {
            group.provider.image.draw(in: NSRect(x: x, y: 1, width: 16, height: 16))
            for (index, metric) in group.metrics.enumerated() {
                let single = group.metrics.count == 1
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .right
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: single ? 11 : 9, weight: .semibold),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph
                ]
                let y: CGFloat = single ? 1 : index % 2 == 0 ? 8 : -1
                NSAttributedString(string: metric.value, attributes: attributes)
                    .draw(in: NSRect(x: x + 20 + CGFloat(index / 2) * 30, y: y, width: 30, height: single ? 16 : 11))
            }
            x += group.width + 8
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = content.summary
        cached = (content, image)
        return image
    }
}
