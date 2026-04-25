#!/bin/bash
# Wrapper for sway-sunshine that tracks the session PID for graceful shutdown
# Written by systemd as ExecStart, replaces /usr/bin/sway directly

RUNTIME_DIR="/run/user/$(id -u)"
PID_FILE="$RUNTIME_DIR/sway-sunshine.pid"

# Write PID file so install.sh can detect/stop a running session
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

exec /usr/bin/sway --config "$HOME/.config/sway-sunshine/config"
