import AppKit
import SwiftUI

@main
struct ProxyUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--import-key"), arguments.count > index + 1 {
            do {
                let key = try String(contentsOfFile: arguments[index + 1], encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { throw ProxyError.message("The key file is empty.") }
                try Keychain.save(key)
                print("Management key saved in macOS Keychain.")
                exit(0)
            } catch {
                fputs("Couldn't import the management key.\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsageView(store: delegate.store)
        } label: {
            if let image = MenuBarRenderer.image(for: delegate.store.menuContent) {
                Image(nsImage: image)
                    .help(delegate.store.menuContent.summary)
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .help("Proxy Usage")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
    }
}
