# BarClaw

A native macOS menu bar app for [OpenClaw](https://openclaw.ai). Sits in your menu bar and gives you an OpenClaw panel with quick access to everything. Your agent chat, sessions, logs, workspace files, and skills all at a glance.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)

---

## What it does

Click the 🦞 icon in your menu bar to open the panel. Seven tabs:

| Tab | What you get |
|-----|-------------|
| **Status** | Gateway health, Telegram status, context usage, session count |
| **Chat** | iMessage-style chat directly to your agent's main session |
| **Sessions** | All active sessions with token counts and context bars |
| **Logs** | Live gateway logs with color coding (errors, warnings, info) |
| **Workspace** | Browse and edit your `.md` workspace files (SOUL, USER, IDENTITY, etc.) |
| **Cron** | View and manage scheduled agent tasks |
| **Skills** | All available skills — ready vs. not installed |

---

## Requirements

- macOS 13 Ventura or later
- [OpenClaw](https://openclaw.ai) installed and gateway running
- Xcode Command Line Tools (for `swift build`)

---

## Install

```bash
git clone https://github.com/mi6uelange7/BarClaw.git
cd BarClaw
swift build -c release
.build/release/BarClaw
```

To keep it running at login, drag `.build/release/BarClaw` into `/Applications` and add it to Login Items in System Settings.

---

## How it works

BarClaw is a Swift Package using SwiftUI's `MenuBarExtra` API (macOS 13+). It has no server, no Electron, no web views — just native Swift talking directly to the `openclaw` CLI.

When you open a tab, it runs an `openclaw` command in a background shell (e.g. `openclaw status --json`, `openclaw sessions --json`) and renders the result as native SwiftUI.

When you send a chat message, it runs `openclaw agent --local -m "your message"` and shows the response inline. The `--local` flag is important — it runs the agent turn in-process and returns the reply directly to BarClaw. **It does not deliver anything to Telegram, Discord, or any other channel.** Your connected channels are completely unaffected by chat messages sent from BarClaw.

```
You click a tab
    → Swift runs: openclaw <command> --json
    → Parses the JSON output
    → Renders it as native SwiftUI views
```

No tokens are stored locally. No persistent process other than the menu bar app itself.

---

## Project structure

```
Sources/BarClaw/
├── App.swift           — @main entry point, MenuBarExtra
├── Service.swift       — Async shell wrapper + data models
├── AppPanel.swift      — Tab bar, header, shared components
├── StatusView.swift    — Gateway status + stats
├── ChatView.swift      — Chat interface
├── SessionsView.swift  — Session list
├── LogsView.swift      — Log viewer
├── WorkspaceView.swift — .md file browser
├── CronView.swift      — Cron job manager
└── SkillsView.swift    — Skills list
```

---

## Build from source

```bash
swift build           # debug
swift build -c release  # optimized
```

Open in Xcode:
```bash
open Package.swift
```
