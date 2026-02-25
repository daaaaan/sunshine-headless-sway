#!/bin/bash
# Shuts down Steam in the headless session and restarts it on the main desktop

# Shut down Steam in the headless session
steam -shutdown

# Wait for it to fully exit
for i in $(seq 1 15); do
    pgrep -x steam > /dev/null 2>&1 || break
    sleep 1
done

# Relaunch Steam on the main desktop (wayland-0)
WAYLAND_DISPLAY=wayland-0 nohup steam -silent > /dev/null 2>&1 &
