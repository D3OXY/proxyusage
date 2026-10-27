import AppKit
import SwiftUI

extension Provider {
    @MainActor var image: NSImage { Self.marks[self]! }

    @MainActor private static let marks: [Provider: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { provider in
        let image = Bundle.main.url(forResource: provider.rawValue, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: provider == .claude ? "asterisk" : "terminal", accessibilityDescription: provider.title)!
        image.isTemplate = true
        return (provider, image)
    })
}
