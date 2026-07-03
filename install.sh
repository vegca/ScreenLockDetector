#!/bin/sh
set -eu

SERVICE_NAME="screen-lock-detector"
PLIST_ID="$USER.screen-lock-detector"
INSTALL_DIR="$HOME/Library/Application Support/ScreenLockDetector"
PLIST_FILE="$HOME/Library/LaunchAgents/$PLIST_ID.plist"

echo "Creating directory..."
mkdir -p "$INSTALL_DIR"

echo "Compiling..."
swiftc -O -whole-module-optimization -o "$SERVICE_NAME" ScreenLockDetector.swift

echo "Installing binary..."
cp "$SERVICE_NAME" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/$SERVICE_NAME"

echo "Creating plist..."
mkdir -p "$HOME/Library/LaunchAgents"
cat >"$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$SERVICE_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/$SERVICE_NAME.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$SERVICE_NAME.error.log</string>
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
EOF

echo "Loading service..."
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

echo "Done! Service status:"
launchctl list | grep "$PLIST_ID"
