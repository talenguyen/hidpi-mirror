#!/bin/bash
# Builds hidpi-mirror from source, installs it to ~/.local/bin and loads the LaunchAgent.
# Touches only: ~/.local/bin/hidpi-mirror, ~/Library/LaunchAgents/local.hidpi-mirror.plist,
# ~/Library/Logs/hidpi-mirror.log. Undo with scripts/uninstall.sh.
set -euo pipefail

NAME=hidpi-mirror
LABEL=local.$NAME
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/$NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/$NAME.log"
DOMAIN="gui/$(id -u)"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: $NAME only runs on macOS" >&2
    exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
    echo "warning: $NAME is only tested on Apple Silicon (this Mac is $(uname -m))" >&2
fi

# Building needs the Swift toolchain, which ships with Xcode or the Command Line Tools.
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: the Swift toolchain was not found.
Install the Xcode Command Line Tools, then run this script again:

    xcode-select --install

(a dialog opens; wait until it finishes). Alternatively install Xcode from the App Store.
MSG
    exit 1
fi

swift build -c release --package-path "$ROOT"

mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
# Stop a running copy first so the binary can be replaced.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
install -m 755 "$ROOT/.build/release/$NAME" "$BIN"

# Expand the plist template with this user's paths (escape sed replacement metacharacters).
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
sed -e "s|@BIN@|$(esc "$BIN")|g" -e "s|@LOG@|$(esc "$LOG")|g" \
    "$ROOT/launchd/$LABEL.plist.template" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed $BIN and $PLIST"
sleep 3
"$BIN" status || true

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "note: $BIN_DIR is not on your PATH; add it to run \`$NAME\` from a shell." ;;
esac
