#!/bin/bash
# Launches a Steam game in the headless Sway session
# Usage: start-steam-game.sh <appid|bigpicture|0>
# Migrates Steam from the main desktop if it's running there

APPID="$1"
WAYLAND_DISPLAY="wayland-1"

# Sway IPC socket for the headless session
SWAYSOCK="/run/user/$(id -u)/sway-sunshine.sock"

export WAYLAND_DISPLAY
export SWAYSOCK

LOG_FILE="$HOME/.config/sway-sunshine/start-steam-game.log"
echo "[$(date)] Environment: WAYLAND_DISPLAY=$WAYLAND_DISPLAY, SWAYSOCK=$SWAYSOCK" >> "$LOG_FILE"
echo "[$(date)] Launching Steam game $APPID" >> "$LOG_FILE"

if [ -z "$APPID" ]; then
    echo "Usage: $0 <steam_appid|bigpicture|0>"
    exit 1
fi

# Shut down any running Steam instance
if pgrep -x steam > /dev/null 2>&1; then
    steam -shutdown 2>/dev/null
    # Wait for graceful shutdown
    for i in $(seq 1 15); do
        pgrep -x steam > /dev/null 2>&1 || break
        sleep 1
    done
    # Force kill only if still running
    if pgrep -x steam > /dev/null 2>&1; then
        pkill -x steam 2>/dev/null
        sleep 2
    fi
fi

# Clean up Steam IPC to prevent instance detection
rm -f ~/.steam/steam.pid 2>/dev/null
rm -f /tmp/steam_singleton_* 2>/dev/null

# Test swaymsg connection
SWAYMSG_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg -t get_outputs 2>&1)
if [ $? -ne 0 ]; then
    echo "[$(date)] ERROR: swaymsg failed to connect: $SWAYMSG_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

# Launch Steam in the headless Sway session
if [ "$APPID" = "bigpicture" ]; then
    EXEC_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg exec "steam steam://open/bigpicture" 2>&1)
    EXEC_CODE=$?
elif [ "$APPID" = "0" ]; then
    EXEC_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg exec steam 2>&1)
    EXEC_CODE=$?
else
    EXEC_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg exec "steam -applaunch $APPID" 2>&1)
    EXEC_CODE=$?
fi

echo "[$(date)] swaymsg exec exit code: $EXEC_CODE, output: $EXEC_OUTPUT" >> "$LOG_FILE"
