#!/bin/bash
# Called by Sunshine as an undo command when a client disconnects
# Reset to default 1080p
SWAYSOCK=/run/user/1000/sway-sunshine.sock swaymsg \
    "output HEADLESS-1 mode 1920x1080@60Hz"
