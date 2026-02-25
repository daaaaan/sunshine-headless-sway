#!/bin/bash
# Launches a Steam game in the headless Sway session
# Usage: start-steam-game.sh <appid|bigpicture|0>
# Migrates Steam from the main desktop if it's running there

APPID="$1"
SWAYSOCK="/run/user/$(id -u)/sway-sunshine.sock"
export SWAYSOCK

if [ -z "$APPID" ]; then
    echo "Usage: $0 <steam_appid|bigpicture|0>"
    exit 1
fi

# Check if Steam is running
if pgrep -x steam > /dev/null 2>&1; then
    # Shut down the existing Steam instance (main desktop)
    steam -shutdown
    # Wait for it to fully exit
    for i in $(seq 1 15); do
        pgrep -x steam > /dev/null 2>&1 || break
        sleep 1
    done
fi

# Launch Steam in the headless Sway session
if [ "$APPID" = "bigpicture" ]; then
    swaymsg exec "steam steam://open/bigpicture"
elif [ "$APPID" = "0" ]; then
    swaymsg exec steam
else
    swaymsg exec "steam -applaunch $APPID"
fi
