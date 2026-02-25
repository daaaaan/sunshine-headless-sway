#!/bin/bash
set -euo pipefail

# Headless Sway + Sunshine Game Streaming Setup
# https://github.com/daaaaan/sunshine-headless-sway

SWAY_CONFIG_DIR="$HOME/.config/sway-sunshine"
SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Headless Sway + Sunshine Installer ==="
echo ""

# Check for required commands
for cmd in sway swaybg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing sway and swaybg..."
        sudo apt install -y sway swaybg
        break
    fi
done

if ! dpkg -s xdg-desktop-portal-wlr &>/dev/null 2>&1; then
    echo "Installing xdg-desktop-portal-wlr..."
    sudo apt install -y xdg-desktop-portal-wlr
fi

# Check for Sunshine
SUNSHINE_PATH=""
if command -v sunshine &>/dev/null; then
    SUNSHINE_PATH="$(command -v sunshine)"
elif [ -f "$HOME/Apps/sunshine.AppImage" ]; then
    SUNSHINE_PATH="$HOME/Apps/sunshine.AppImage"
else
    echo ""
    echo "Sunshine not found. Please install it from:"
    echo "  https://github.com/LizardByte/Sunshine/releases"
    echo ""
    read -rp "Enter the path to your Sunshine binary/AppImage: " SUNSHINE_PATH
    if [ ! -f "$SUNSHINE_PATH" ]; then
        echo "Error: $SUNSHINE_PATH not found"
        exit 1
    fi
fi

echo "Using Sunshine at: $SUNSHINE_PATH"

# Detect Wayland display for the headless session
MAIN_WAYLAND=$(ls /run/user/$(id -u)/wayland-* 2>/dev/null | grep -v lock | sort | tail -1 | xargs basename)
if [ "$MAIN_WAYLAND" = "wayland-0" ]; then
    HEADLESS_DISPLAY="wayland-1"
else
    HEADLESS_DISPLAY="wayland-$((${MAIN_WAYLAND##wayland-} + 1))"
fi
echo "Main display: $MAIN_WAYLAND, headless will be: $HEADLESS_DISPLAY"

# Detect UID for socket paths
USER_ID=$(id -u)
SOCKET_PATH="/run/user/$USER_ID/sway-sunshine.sock"

echo ""
echo "Installing config files..."

# Sway config
mkdir -p "$SWAY_CONFIG_DIR"
cp "$SCRIPT_DIR/sway-sunshine/config" "$SWAY_CONFIG_DIR/config"

# Resolution scripts (template the user ID into them)
sed "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    "$SCRIPT_DIR/sway-sunshine/set-resolution.sh" > "$SWAY_CONFIG_DIR/set-resolution.sh"
sed "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    "$SCRIPT_DIR/sway-sunshine/reset-resolution.sh" > "$SWAY_CONFIG_DIR/reset-resolution.sh"
chmod +x "$SWAY_CONFIG_DIR/set-resolution.sh"
chmod +x "$SWAY_CONFIG_DIR/reset-resolution.sh"

# Sunshine config (only if not already configured)
mkdir -p "$SUNSHINE_CONFIG_DIR"
if [ ! -f "$SUNSHINE_CONFIG_DIR/sunshine.conf" ]; then
    cp "$SCRIPT_DIR/sunshine/sunshine.conf" "$SUNSHINE_CONFIG_DIR/sunshine.conf"
    echo "Created sunshine.conf"
elif ! grep -q "^sink" "$SUNSHINE_CONFIG_DIR/sunshine.conf"; then
    echo "sink = sink-sunshine-stereo" >> "$SUNSHINE_CONFIG_DIR/sunshine.conf"
    echo "Added audio sink to existing sunshine.conf"
else
    echo "sunshine.conf already configured, skipping"
fi

# Apps config (only if not already present)
if [ ! -f "$SUNSHINE_CONFIG_DIR/apps.json" ]; then
    sed "s|/home/YOUR_USER/|$HOME/|g" \
        "$SCRIPT_DIR/sunshine/apps.json" > "$SUNSHINE_CONFIG_DIR/apps.json"
    echo "Created apps.json"
else
    echo "apps.json already exists, skipping (see sunshine/apps.json for reference)"
fi

# Systemd services
mkdir -p "$SYSTEMD_DIR"

sed -e "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    "$SCRIPT_DIR/systemd/sway-sunshine.service" > "$SYSTEMD_DIR/sway-sunshine.service"

sed -e "s|WAYLAND_DISPLAY=wayland-1|WAYLAND_DISPLAY=$HEADLESS_DISPLAY|g" \
    -e "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    -e "s|ExecStart=.*|ExecStart=$SUNSHINE_PATH|g" \
    "$SCRIPT_DIR/systemd/sunshine-headless.service" > "$SYSTEMD_DIR/sunshine-headless.service"

echo "Installed systemd services"

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable sway-sunshine.service
systemctl --user enable sunshine-headless.service

echo ""
echo "=== Installation complete ==="
echo ""
echo "To start streaming now:"
echo "  systemctl --user start sway-sunshine.service"
echo ""
echo "To check status:"
echo "  systemctl --user status sway-sunshine sunshine-headless"
echo ""
echo "To add Steam games to Moonlight, edit:"
echo "  $SUNSHINE_CONFIG_DIR/apps.json"
echo ""
echo "Pair with Moonlight at: https://$(hostname):47990"
echo ""

read -rp "Start the services now? [Y/n] " START
if [[ "${START:-Y}" =~ ^[Yy]?$ ]]; then
    systemctl --user start sway-sunshine.service
    echo "Services started. Open Moonlight to connect."
fi
