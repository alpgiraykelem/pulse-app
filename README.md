# Activity Tracker

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Privacy-first, automatic time tracking for macOS.** Runs silently in your menu bar, tracks which apps and windows you use, and generates beautiful HTML reports. No cloud, no accounts, no data leaves your Mac.

![Activity Tracker Screenshot](docs/screenshot.png)

## Install

```bash
git clone https://github.com/alpgiraykelem/activity-tracker.git
cd activity-tracker
./Scripts/install.sh
```

Then open **Activity Tracker** from Spotlight (`Cmd+Space`) or the Applications folder.

> Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

## Features

- **Automatic window tracking** — detects your active app and window every 2 seconds
- **Menu bar control** — start, pause, or stop from the menu bar icon
- **Smart site separation** — YouTube, GitHub, ChatGPT, Claude, and more are tracked as separate apps inside your browser
- **Terminal monitoring** — tracks background processes like compiling, git, and npm scripts
- **Safari URL tracking** — logs the current tab URL and title
- **Now playing** — captures Spotify and Apple Music tracks alongside your work
- **Idle & sleep detection** — auto-pauses after 10 minutes of inactivity, detects screen lock and sleep
- **HTML reports** — daily reports with donut charts, timeline views, and per-app breakdowns
- **Historical reports** — browse any past day, all stored in local SQLite

## Usage

Activity Tracker runs as a menu bar app by default. You can also use the CLI:

```bash
# Check status
activity-tracker status

# Generate today's report
activity-tracker report

# Generate report for a specific date
activity-tracker report --date 2025-01-15

# Start in headless mode (no menu bar)
activity-tracker start --headless

# Stop tracking
activity-tracker stop

# Set up auto-start on login
activity-tracker install

# Remove auto-start
activity-tracker uninstall
```

## How It Works

Activity Tracker polls the frontmost application every 2 seconds using macOS accessibility APIs. It extracts:

- App name and bundle ID
- Window title
- URLs from Safari, Chrome, Brave, and Firefox
- Now playing info from Spotify and Apple Music
- Working directory from Terminal and iTerm

Records are batched and written to a local SQLite database at `~/Library/Application Support/ActivityTracker/activity.db`. Reports are generated as standalone HTML files in the same directory.

## Privacy

**No data ever leaves your Mac.**

- Zero network calls — the only dependencies are [SQLite.swift](https://github.com/stephencelis/SQLite.swift) and [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- All data stored locally in SQLite
- No analytics, no telemetry, no tracking SDKs
- Fully open source — audit every line

Verify it yourself:

```bash
grep -r "URLSession\|NSURLConnection\|Network.framework" Sources/
# 0 matches
```

## Data Location

| File | Path |
|------|------|
| Database | `~/Library/Application Support/ActivityTracker/activity.db` |
| Reports | `~/Library/Application Support/ActivityTracker/reports/` |
| Logs | `~/Library/Logs/ActivityTracker/` |
| LaunchAgent | `~/Library/LaunchAgents/com.alpgiraykelem.activity-tracker.plist` |

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools
- Accessibility permission (prompted on first launch)

## Uninstall

```bash
# Remove the app
rm -rf "/Applications/Activity Tracker.app"

# Remove data (optional)
rm -rf ~/Library/Application\ Support/ActivityTracker
rm -f ~/Library/LaunchAgents/com.alpgiraykelem.activity-tracker.plist
```

## License

MIT License. See [LICENSE](LICENSE) for details.

---

Built by [Alpgiray Kelem](https://www.linkedin.com/in/alpgiray-kelem/)
