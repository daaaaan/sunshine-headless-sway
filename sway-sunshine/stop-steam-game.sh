#!/bin/bash
# Shuts down Steam in the headless session and restarts it on the main desktop

# Shut down Steam in the headless session
steam -shutdown 2>/dev/null

# Wait for it to fully exit
for i in $(seq 1 15); do
    pgrep -x steam > /dev/null 2>&1 || break
    sleep 1
done

# Force kill if still running
if pgrep -x steam > /dev/null 2>&1; then
    pkill -x steam 2>/dev/null
    sleep 2
fi

# Clean up IPC before relaunching
rm -f ~/.steam/steam.pid 2>/dev/null
rm -f /tmp/steam_singleton_* 2>/dev/null

# Relaunch Steam on the main desktop (wayland-0)
WAYLAND_DISPLAY=wayland-0 nohup steam -silent > /dev/null 2>&1 &
