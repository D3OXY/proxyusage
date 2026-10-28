import AppKit
import ServiceManagement
import SwiftUI

struct UsageView: View {
    @Bindable var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            if store.showingSettings {
                HStack {
                    Button { store.showingSettings = false } label: {
                        Label("Connection", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain).font(.headline)
                    Spacer()
                }
                .padding(16)
                ConnectionView(store: store)
            } else {
                ScrollView {
                    UsageDashboard(store: store)
                }
                .scrollIndicators(.never)
                .frame(height: dashboardHeight)
            }
            footer
        }
        .frame(width: 350)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            if store.updatedAt.map({ Date.now.timeIntervalSince($0) >= 300 }) ?? true {
                await store.refresh()
            }
        }
    }

    private var dashboardHeight: CGFloat {
        let rows = store.accounts.reduce(0) { $0 + max(1, $1.limits.count) }
        let height = CGFloat(rows) * 87 + CGFloat(store.accounts.count) * 65 + 24
        return min(520, max(150, height + (store.error == nil ? 0 : 70)))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Proxy Usage").font(.system(size: 10, weight: .medium))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if store.refreshing {
                        Text("Updating…")
                    } else if let next = store.nextRefreshAt {
                        let seconds = max(0, Int(ceil(next.timeIntervalSince(context.date))))
                        Text("Updates in \(seconds / 60)m \(seconds % 60)s").monospacedDigit()
                    } else {
                        Text("Updates every 5 min")
                    }
                }
                .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            Spacer()
            if store.refreshing {
                ProgressView().controlSize(.mini)
            } else {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .help("Refresh · ⌘R").accessibilityLabel("Refresh").keyboardShortcut("r")
            }
            Menu {
                Button("Connection settings…") { store.showingSettings = true }
                if let base = try? ProxyClient.baseURL(from: store.proxyURL) {
                    Link("Open CLIProxy dashboard", destination: base.appendingPathComponent("management.html"))
                }
                Divider()
                Button("Quit Proxy Usage") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape").frame(width: 24, height: 24) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Options")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.bar)
    }
}

struct UsageDashboard: View {
    @Bindable var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                if !store.accounts.isEmpty {
                    Text("Showing the last reading.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.accounts.isEmpty && !store.refreshing && store.error == nil {
                ContentUnavailableView("No accounts", systemImage: "person.crop.circle",
                                       description: Text("Connect a Claude Code or Codex account in CLIProxy."))
            }
            ForEach(store.accounts) { account in
                accountSection(account)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountSection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(account.provider.title).font(.system(size: 13, weight: .semibold))
                    if let plan = account.plan {
                        Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(nsImage: account.provider.image).resizable()
                        .frame(width: 18, height: 18).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(account.name).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 20) {
                if let error = account.error {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(account.limits) { limit in
                    LimitRow(limit: limit, pinned: store.pins.contains { $0.id == account.pinID(limit) }) {
                        store.togglePin(account: account, limit: limit)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Adapted from OpenUsage's WidgetRowView: label, capsule meter, used amount and reset time.
private struct LimitRow: View {
    let limit: UsageLimit
    let pinned: Bool
    let togglePin: () -> Void

    private var color: Color {
        limit.usedPercent >= 95 ? .red : limit.usedPercent >= 80 ? .orange : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(limit.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: togglePin) {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(pinned ? Color.accentColor : .secondary)
                        .frame(width: 22, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Remove from menu bar" : "Show in menu bar")
                .accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(limit.title)")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: geometry.size.width * Double(limit.used) / 100)
                }
            }
            .frame(height: 5).accessibilityHidden(true)
            HStack(alignment: .top) {
                Text("\(limit.used)% used").monospacedDigit()
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(limit.resetTimeText(now: context.date))
                        if limit.resetsAt != nil {
                            Text(limit.resetText(now: context.date)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .help(limit.resetsAt?.formatted(date: .complete, time: .shortened) ?? "No reset time reported")
            }
            .font(.system(size: 11))
        }
    }
}

private struct ConnectionView: View {
    @Bindable var store: UsageStore
    @State private var url = ""
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CLIProxy URL").font(.caption).foregroundStyle(.secondary)
                TextField("http://localhost:8317", text: $url).textContentType(.URL)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Management key").font(.caption).foregroundStyle(.secondary)
                SecureField("Leave blank to keep saved key", text: $key)
                Text("Stored in macOS Keychain.").font(.caption2).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            Button("Save and connect") {
                Task {
                    do {
                        try await store.saveConnection(url: url, newKey: key)
                        key = ""
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent).disabled(store.refreshing)
            Divider()
            Toggle("Start at login", isOn: Binding(
                get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                set: { store.setLaunchAtLogin($0) }
            ))
            if store.loginStatus == .requiresApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = store.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !store.pins.isEmpty {
                Divider()
                Text("Menu bar limits").font(.caption).foregroundStyle(.secondary)
                ForEach(store.pins) { pin in
                    HStack {
                        Text(pin.label).font(.caption).lineLimit(1)
                        Spacer()
                        Button { store.removePin(pin.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).accessibilityLabel("Unpin \(pin.label)")
                    }
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .onAppear { url = store.proxyURL }
    }
}
