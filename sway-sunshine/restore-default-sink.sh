#!/bin/bash
# Restores the host's default audio sink after Sunshine changes it.
# Sunshine sets audio_sink as the system default when a client connects.
# Uses systemd-run to spawn a detached watcher that survives prep-cmd cleanup.
# Skips restoration if the new default is sink-sunshine-stereo (Sunshine's null sink).

# Get the current default sink ID from wpctl
# Format: " │  *   44. Komplete Audio 2 ..."
SINK_ID=$(wpctl status 2>/dev/null | grep -A20 'Sinks:' | grep '\*' | head -1 | grep -oE '[0-9]+' | head -1)

if [ -z "$SINK_ID" ]; then
    exit 0
fi

# Clean up any previous instance
systemctl --user stop sunshine-sink-restore 2>/dev/null
systemctl --user reset-failed sunshine-sink-restore 2>/dev/null

# Launch a detached watcher via systemd-run (survives prep-cmd cleanup)
systemd-run --user --no-block --unit=sunshine-sink-restore \
    bash -c 'for i in $(seq 1 30); do sleep 1; CUR=$(wpctl status 2>/dev/null | grep -A20 "Sinks:" | grep "\*" | head -1 | grep -oE "[0-9]+" | head -1); if [ "$CUR" != "'"$SINK_ID"'" ] && [ -n "$CUR" ]; then CUR_NAME=$(wpctl inspect $CUR 2>/dev/null | grep "node.name" | cut -d= -f2 | xargs); if [ "$CUR_NAME" = "sink-sunshine-stereo" ]; then continue; fi; wpctl set-default '"$SINK_ID"'; exit 0; fi; done'
