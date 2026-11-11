#!/bin/bash
# Stops the agent (restores the display's native mode) and removes everything install.sh created.
set -euo pipefail

NAME=hidpi-mirror
LABEL=local.$NAME
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/$NAME" "$HOME/Library/Logs/$NAME.log"
echo "uninstalled $LABEL"
