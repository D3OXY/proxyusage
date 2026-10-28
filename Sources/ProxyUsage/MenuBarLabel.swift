import AppKit

struct MenuBarContent: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        let label: String
        let used: Int?
        let window: String
        var value: String { used.map { "\($0)%" } ?? "—" }
    }

    struct Group: Equatable, Sendable {
        let provider: Provider
        let metrics: [Metric]

        @MainActor func font(rows: Int) -> NSFont {
            .monospacedDigitSystemFont(ofSize: rows == 2 && metrics.count == 1 ? 11 : 9, weight: .semibold)
        }

        @MainActor func columnWidths(rows: Int) -> [CGFloat] {
            stride(from: 0, to: metrics.count, by: rows).map { start in
                // Reserve two digits so ordinary usage updates keep the strip steady.
                let values = ["99%"] + metrics[start..<min(start + rows, metrics.count)].map(\.value)
                return ceil(values.map { ($0 as NSString).size(withAttributes: [.font: font(rows: rows)]).width }.max() ?? 0) + 1
            }
        }
    }

    let groups: [Group]
    var rows: Int { groups.count > 1 ? 1 : 2 }
    var iconSize: CGFloat { groups.count > 1 ? 9 : 14 }

    var alignedMetrics: [[Metric?]] {
        var windows: [String] = []
        for group in groups {
            var pending = windows
            for metric in group.metrics {
                if let index = pending.firstIndex(of: metric.window) {
                    pending.remove(at: index)
                } else {
                    windows.append(metric.window)
                }
            }
        }
        return groups.map { group in
            var pending = group.metrics
            return windows.map { window in
                guard let index = pending.firstIndex(where: { $0.window == window }) else { return nil }
                return pending.remove(at: index)
            }
        }
    }

    @MainActor var columnWidths: [CGFloat] {
        guard rows == 1 else { return groups.first?.columnWidths(rows: rows) ?? [] }
        let aligned = alignedMetrics
        return (aligned.first ?? []).indices.map { column in
            let values = ["99%"] + aligned.compactMap { $0[column]?.value }
            let font = groups[0].font(rows: rows)
            return ceil(values.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 1
        }
    }

    @MainActor var width: CGFloat {
        let columns = columnWidths
        return iconSize + 2 + columns.reduce(0, +) + CGFloat(max(0, columns.count - 1)) * 3
    }
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
                let accountPrefix = account.map { "\(provider.shortName) \($0.name) " }
                let prefix = accountPrefix.flatMap { pin.label.hasPrefix($0) ? $0 : nil } ?? "\(provider.shortName) "
                let savedTitle = pin.label.hasPrefix(prefix) ? String(pin.label.dropFirst(prefix.count)) : pin.label
                let window = (limit?.title ?? savedTitle).replacingOccurrences(of: "5-hour", with: "5h")
                return Metric(label: pin.label, used: unavailable ? nil : limit?.used, window: window)
            }
            return metrics.isEmpty ? nil : Group(provider: provider, metrics: metrics)
        }
    }
}

// Adapted from OpenUsage. Two providers share the strip vertically; a lone provider stacks its values.
@MainActor enum MenuBarRenderer {
    private static var cached: (MenuBarContent, NSImage)?

    static func image(for content: MenuBarContent) -> NSImage? {
        guard !content.groups.isEmpty else { return nil }
        if let cached, cached.0 == content { return cached.1 }
        let image = NSImage(size: NSSize(width: content.width, height: 18))
        image.lockFocus()
        let aligned = content.alignedMetrics
        let widths = content.columnWidths
        for (index, group) in content.groups.enumerated() {
            let metrics: [MenuBarContent.Metric?] = content.rows == 1 ? aligned[index] : group.metrics.map { $0 }
            let providerY: CGFloat = content.rows == 1 ? CGFloat(1 - index) * 9 : 2
            group.provider.image.draw(in: NSRect(x: 0, y: providerY, width: content.iconSize, height: content.iconSize))
            let single = content.rows == 2 && group.metrics.count == 1
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            let attributes: [NSAttributedString.Key: Any] = [
                .font: group.font(rows: content.rows),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            var columnX = content.iconSize + 2
            for (column, width) in widths.enumerated() {
                for row in 0..<min(content.rows, metrics.count - column * content.rows) {
                    guard let metric = metrics[column * content.rows + row] else { continue }
                    let y: CGFloat = content.rows == 1 ? providerY - 1 : single ? 1 : row == 0 ? 8 : -1
                    NSAttributedString(string: metric.value, attributes: attributes)
                        .draw(in: NSRect(x: columnX, y: y, width: width, height: single ? 16 : 11))
                }
                columnX += width + 3
            }
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = content.summary
        cached = (content, image)
        return image
    }
}
