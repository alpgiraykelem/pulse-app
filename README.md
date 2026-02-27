<div align="center">

# Pulse

**Your work's pulse, captured automatically.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-10b981?style=for-the-badge)](#license)
[![100% Offline](https://img.shields.io/badge/100%25-Offline-6366f1?style=for-the-badge&logo=lock&logoColor=white)](#privacy)
[![GitHub Release](https://img.shields.io/github/v/release/alpgiraykelem/pulse-app?style=for-the-badge&color=f59e0b)](https://github.com/alpgiraykelem/pulse-app/releases/latest)

Privacy-first, automatic time tracking for macOS. Runs silently in your menu bar, tracks which apps and windows you use, and generates beautiful HTML reports.

**No cloud. No accounts. No data leaves your Mac.**

[Download Latest Release](https://github.com/alpgiraykelem/pulse-app/releases/latest) · [Website](https://alpgiraykelem.github.io/pulse-app/) · [Report Bug](https://github.com/alpgiraykelem/pulse-app/issues)

</div>

---

## Why Pulse?

Manual time trackers require you to start/stop timers, categorize tasks, and remember what you worked on. Pulse does all of this automatically.

| | Manual Time Trackers | Pulse |
|---|---|---|
| **Tracking** | Start/stop timers manually | Automatic — detects active app every 2s |
| **Project assignment** | Select project per entry | Pattern detection suggests rules, auto-classifies |
| **Terminal work** | Not tracked | Builds, deploys, git — all captured |
| **Spotify / Music** | Not tracked | Now playing alongside your work |
| **Data location** | Cloud servers | 100% local on your Mac |
| **Cost** | $10-30/mo per user | Free & open source |
| **Setup time** | Account creation, team setup | Open app, grant permission, done |

---

## Features

### Automatic Window Tracking
Detects your active app and window every 2 seconds. No timers to start, no buttons to click. Just work — Pulse captures everything.

### Brand & Project Hierarchy
Organize your work by client (brand) and project. Assign activities automatically with 7 rule types: URL domain, folder path, window title, Figma file, bundle ID, page title, terminal folder.

### Smart Pattern Detection
Scans your unassigned activities and detects patterns in URLs, folders, window titles, and Figma files. Suggests clients, projects, and matching rules — no AI, just smart pattern recognition. One click to accept.

### Smart Site Separation
YouTube, GitHub, ChatGPT, Claude, and other sites are tracked as separate "apps" inside your browser — not just lumped under "Safari" or "Chrome".

### Background Terminal Monitoring
Tracks builds, deploys, git operations, and long-running processes. Parses project names from your working directory.

### Beautiful HTML Reports
Daily reports with donut charts, activity timelines, per-app breakdowns, and in-report project assignment.

### Live SPA Dashboard
A full single-page dashboard served from your menu bar. Filter by client, switch between time periods (All Time / Week / Month / Custom), and see exactly where every minute goes.

### Parallel Work Tracking
Working on a deploy while reviewing a PR in another terminal? Pulse tracks both simultaneously — each project gets its own clock. No project switching needed.

### Bulk Assignment
Select multiple activities with checkboxes, then assign them all to a project at once. Select all per app, or cherry-pick individual windows.

### Native macOS Settings
Manage brands, projects, and rules from a native settings window. Keyboard shortcut: `Cmd+,`

### Now Playing
Captures Spotify and Apple Music tracks alongside your work — see what you were listening to during any session.

---

## Install

### Option 1: Download the .app (Recommended)

1. Download `Pulse-v1.0.0-macOS.zip` from [Releases](https://github.com/alpgiraykelem/pulse-app/releases/latest)
2. Unzip and move `Pulse.app` to `/Applications`
3. Open from Spotlight or Applications folder
4. Grant Accessibility permission when prompted

### Option 2: Build from source

```bash
git clone https://github.com/alpgiraykelem/pulse-app.git
cd pulse-app && ./Scripts/install.sh
```

> Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

---

## Usage

Pulse runs as a menu bar app by default. Click the menu bar icon to:
- View today's tracked time
- Open HTML reports for any day
- Run AI analysis on your work patterns
- Open Settings to manage brands, projects, and rules

### CLI

```bash
# Check status
pulse status

# Generate today's HTML report
pulse report today --html

# Show this week's summary
pulse report week

# Export last 30 days as JSON
pulse report export --month

# Start in headless mode (no menu bar)
pulse start --headless

# Stop tracking
pulse stop

# Set up auto-start on login
pulse install
```

---

## How It Works

Pulse polls the frontmost application every 2 seconds using macOS accessibility APIs. It extracts:

- App name and bundle ID
- Window title
- URLs from Safari, Chrome, Brave, and Firefox
- Now playing info from Spotify and Apple Music
- Working directory from Terminal and iTerm
- Figma file names via AXUIElement API

Records are batched into heartbeats and merged into activity sessions in a local SQLite database. A local HTTP API server powers the Settings UI and in-report interactions.

---

## Privacy

**No data ever leaves your Mac.**

- Zero network calls — no analytics, no telemetry, no tracking SDKs
- All data stored locally in SQLite at `~/Library/Application Support/ActivityTracker/`
- Only two dependencies: [SQLite.swift](https://github.com/stephencelis/SQLite.swift) and [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- Fully open source — audit every line

Verify it yourself:

```bash
grep -r "URLSession\|NSURLConnection\|Network.framework" Sources/
# 0 matches
```

---

## Data Location

| File | Path |
|------|------|
| Database | `~/Library/Application Support/ActivityTracker/activity.db` |
| Reports | `~/Library/Application Support/ActivityTracker/reports/` |
| LaunchAgent | `~/Library/LaunchAgents/com.alpgiraykelem.activity-tracker.plist` |

---

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (prompted on first launch)
- Screen Recording permission (for window titles)

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI | NSStatusItem (menu bar) + WKWebView (settings) |
| Database | SQLite via SQLite.swift |
| Reports | HTML + CSS + JavaScript |
| API | Local HTTP server (NWListener) |
| CLI | swift-argument-parser |

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/Pulse.app

# Remove data (optional)
rm -rf ~/Library/Application\ Support/ActivityTracker
rm -f ~/Library/LaunchAgents/com.alpgiraykelem.activity-tracker.plist
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

Built by [Alpgiray Kelem](https://www.linkedin.com/in/alpgiray-kelem/)

**Stop starting timers. Start getting real data.**

</div>
