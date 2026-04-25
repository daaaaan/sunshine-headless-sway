#!/bin/bash
# Launches a Lutris game in the headless Sway session
# Usage: start-lutris-game.sh <lutris_game_id>
#   <lutris_game_id> — launches the game via lutris:rungameid/<id>
#   lutris            — opens the Lutris launcher UI

GAME_ID="$1"
WAYLAND_DISPLAY="wayland-1"

SWAYSOCK="/run/user/$(id -u)/sway-sunshine.sock"

export WAYLAND_DISPLAY
export SWAYSOCK

LOG_FILE="$HOME/.config/sway-sunshine/start-lutris-game.log"
echo "[$(date)] Environment: WAYLAND_DISPLAY=$WAYLAND_DISPLAY, SWAYSOCK=$SWAYSOCK" >> "$LOG_FILE"

if [ -z "$GAME_ID" ]; then
    echo "Usage: $0 <lutris_game_id|lutris>"
    exit 1
fi

# Open Lutris launcher UI
if [ "$GAME_ID" = "lutris" ]; then
    EXEC_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg exec lutris --open 2>&1)
    EXEC_CODE=$?
    echo "[$(date)] swaymsg exec exit code: $EXEC_CODE, output: $EXEC_OUTPUT" >> "$LOG_FILE"
    exit 0
fi

echo "[$(date)] Launching Lutris game $GAME_ID" >> "$LOG_FILE"

# Test swaymsg connection
SWAYMSG_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg -t get_outputs 2>&1)
if [ $? -ne 0 ]; then
    echo "[$(date)] ERROR: swaymsg failed to connect: $SWAYMSG_OUTPUT" >> "$LOG_FILE"
    exit 1
fi

# Launch Lutris game in the headless Sway session
EXEC_OUTPUT=$(SWAYSOCK="$SWAYSOCK" swaymsg exec "lutris lutris:rungameid/$GAME_ID" 2>&1)
EXEC_CODE=$?

echo "[$(date)] swaymsg exec exit code: $EXEC_CODE, output: $EXEC_OUTPUT" >> "$LOG_FILE"
