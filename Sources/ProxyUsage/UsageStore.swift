import Foundation
import Observation
import ServiceManagement

struct PinnedLimit: Codable, Identifiable, Sendable {
    let id: String
    let label: String
}

@MainActor @Observable
final class UsageStore {
    var accounts: [AccountUsage] = []
    var refreshing = false
    var error: String?
    var updatedAt: Date?
    var nextRefreshAt: Date?
    var showingSettings = false
    var proxyURL = UserDefaults.standard.string(forKey: "proxyURL") ?? "http://localhost:8317"
    var pins: [PinnedLimit] = {
        guard let data = UserDefaults.standard.data(forKey: "pins") else { return [] }
        return (try? JSONDecoder().decode([PinnedLimit].self, from: data)) ?? []
    }()
    var loginStatus = SMAppService.mainApp.status
    var loginError: String?
    @ObservationIgnored private var autoRefresh: Task<Void, Never>?

    var menuContent: MenuBarContent { MenuBarContent(pins: pins, accounts: accounts, unavailable: error != nil) }

    func refresh() async {
        guard !refreshing else { return }
        autoRefresh?.cancel()
        autoRefresh = nil
        nextRefreshAt = nil
        refreshing = true
        defer {
            refreshing = false
            nextRefreshAt = .now.addingTimeInterval(300)
            autoRefresh = Task {
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
                autoRefresh = nil
                await refresh()
            }
        }
        do {
            guard let key = try Keychain.read(), !key.isEmpty else {
                showingSettings = true
                return
            }
            let client = ProxyClient(baseURL: try ProxyClient.baseURL(from: proxyURL), key: key)
            let files = try await client.accounts()
            var results: [AccountUsage] = []
            // Small batches avoid flooding the proxy when several accounts are connected.
            for start in stride(from: 0, to: files.count, by: 4) {
                let batch = files[start..<min(start + 4, files.count)]
                results += await withTaskGroup(of: AccountUsage.self) { group in
                    for file in batch { group.addTask { await client.usage(for: file) } }
                    var values: [AccountUsage] = []
                    for await value in group { values.append(value) }
                    return values
                }
            }
            accounts = results.sorted {
                ($0.provider.rawValue, $0.name, $0.id) < ($1.provider.rawValue, $1.name, $1.id)
            }
            error = nil
            updatedAt = .now
        } catch {
            self.error = ProxyClient.message(for: error)
        }
    }

    func saveConnection(url: String, newKey: String) async throws {
        guard !refreshing else { throw ProxyError.message("Wait for the current refresh to finish.") }
        let baseURL = try ProxyClient.baseURL(from: url)
        if !newKey.isEmpty { try Keychain.save(newKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let key = try Keychain.read(), !key.isEmpty else {
            throw ProxyError.message("Enter the proxy management key, not the client API key.")
        }
        proxyURL = baseURL.absoluteString
        UserDefaults.standard.set(proxyURL, forKey: "proxyURL")
        accounts = []
        updatedAt = nil
        showingSettings = false
        await refresh()
    }

    func togglePin(account: AccountUsage, limit: UsageLimit) {
        let id = account.pinID(limit)
        if pins.contains(where: { $0.id == id }) {
            pins.removeAll { $0.id == id }
        } else {
            let multiple = accounts.filter { $0.provider == account.provider }.count > 1
            let name = multiple ? "\(account.provider.shortName) \(account.name)" : account.provider.shortName
            let label = limit.title.replacingOccurrences(of: "5-hour", with: "5h")
            pins.append(PinnedLimit(id: id, label: "\(name) \(label)"))
        }
        savePins()
    }

    func removePin(_ id: String) {
        pins.removeAll { $0.id == id }
        savePins()
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) { UserDefaults.standard.set(data, forKey: "pins") }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            loginError = nil
        } catch {
            loginStatus = SMAppService.mainApp.status
            loginError = "Couldn't change launch at login. Check System Settings → General → Login Items."
        }
    }

    func start() {
        if !UserDefaults.standard.bool(forKey: "loginConfigured") {
            setLaunchAtLogin(true)
            if loginStatus == .enabled || loginStatus == .requiresApproval {
                UserDefaults.standard.set(true, forKey: "loginConfigured")
            }
        }
        Task { await refresh() }
    }
}
