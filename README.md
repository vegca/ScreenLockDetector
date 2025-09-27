# ScreenLockDetector

macOS service that executes Shortcuts based on screen lock/unlock events.

## Setup

1. Edit `ScreenLockDetector.swift` and update:
```swift
static let setOnShortcut = "Your Unlock Shortcut"
static let setOffShortcut = "Your Lock Shortcut"
```

2. Run installation:
```bash
./install.sh
```

## Manual Commands

```bash
# View logs
tail -f /tmp/screen-lock-detector.log

# Stop service
launchctl stop $USER.screen-lock-detector

# Uninstall
launchctl unload ~/Library/LaunchAgents/$USER.screen-lock-detector.plist
rm ~/Library/LaunchAgents/$USER.screen-lock-detector.plist
rm -rf ~/Library/Application\ Support/ScreenLockDetector
```

## Requirements

- macOS 15.5+
- Shortcuts configured in Shortcuts.app
