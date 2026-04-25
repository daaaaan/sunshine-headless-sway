#!/bin/bash
# Stops a Lutris game launched via start-lutris-game.sh
# Usage: stop-lutris-game.sh <lutris_game_id>

GAME_ID="$1"

if [ -z "$GAME_ID" ]; then
    echo "Usage: $0 <lutris_game_id>"
    exit 1
fi

# Find and kill the game process matching this game's rungameid URI
# Lutris launches the game with the rungameid URI in its process args
MATCHED_PIDS=$(pgrep -f "lutris:rungameid/$GAME_ID" 2>/dev/null || true)

if [ -z "$MATCHED_PIDS" ]; then
    exit 0
fi

# Send SIGTERM to matched processes
for PID in $MATCHED_PIDS; do
    kill "$PID" 2>/dev/null
done

# Wait for graceful shutdown
for i in $(seq 1 15); do
    ALL_EXITED=true
    for PID in $MATCHED_PIDS; do
        if kill -0 "$PID" 2>/dev/null; then
            ALL_EXITED=false
            break
        fi
    done
    $ALL_EXITED && break
    sleep 1
done

# Force kill any remaining processes
for PID in $MATCHED_PIDS; do
    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null
    fi
done

sleep 1

# Final cleanup: kill any remaining processes with this game's rungameid
pkill -f "lutris:rungameid/$GAME_ID" 2>/dev/null
