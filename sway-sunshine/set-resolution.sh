#!/bin/bash
# Called by Sunshine as a prep command when a client connects
# Dynamically sets the headless output to match the Moonlight client
SWAYSOCK=/run/user/1000/sway-sunshine.sock swaymsg \
    "output HEADLESS-1 mode ${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}Hz"

# Let the display mode settle before Sunshine starts capturing
sleep 1
