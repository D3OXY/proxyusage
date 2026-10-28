# Proxy Usage

A small macOS menu bar app for Claude Code and Codex accounts connected to one CLIProxyAPI server. No dependencies. macOS 14 or later.

Click the gauge in the menu bar to see each account's percent used and reset times in your device's timezone, with a countdown. Click a pin next to any limit to keep it in the menu bar. Unpinned limits stay in the popover. The footer counts down to the next update. Usage refreshes every five minutes; the manual refresh button restarts that countdown.

Pinned limits use OpenUsage's compact layout: one monochrome provider mark and bare percentages used, stacked two high. Two pins per provider take 108 points total. Names and reset times stay in the popover or the menu bar tooltip. The popover uses quiet grouped cards, blue meters and native footer material.

Settings holds the proxy URL, management key, and Start at login toggle. The key is stored in macOS Keychain under `dev.deoxy.proxyusage`, account `management-key`. The URL and pins live in UserDefaults. No provider OAuth tokens are downloaded or stored. The app only uses `auth-files` and `api-call` on CLIProxy's management API, with read requests to the providers' usage endpoints.

Claude includes session, weekly, model-specific and extra usage windows when reported. Codex includes session, weekly or monthly, code-review and additional model windows when reported. Missing windows are omitted. A failed read shows an error instead of a quota estimate. Menu bar values show a dash if their account cannot be read.

## Build and install

Requires the Xcode command line tools and Swift 6 or later.

```sh
git clone https://github.com/D3OXY/proxyusage.git
cd proxyusage
swift test
./scripts/build.sh --install
open "/Applications/Proxy Usage.app"
```

The build script produces an ad-hoc signed app for the current Mac. No Xcode project, third-party dependencies, updater, analytics, proxy server, or account login flow. On first launch it registers with macOS Login Items. If macOS requires approval, Settings shows a link to approve it.

Open Connection settings and enter your CLIProxyAPI URL and management key. The default URL is `http://localhost:8317`. For a remote server, use HTTPS or a trusted private network. The management key grants access to your proxy's management API; keep it private.

To rebuild an existing install, quit the app, remove `/Applications/Proxy Usage.app`, then run the install command again. Keychain, URL and pins survive reinstalling. This app is for local personal use and isn't notarized.

MIT licensed. The meter layout is adapted from [OpenUsage](https://github.com/robinebers/openusage). Usage is read through [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)'s management API. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
