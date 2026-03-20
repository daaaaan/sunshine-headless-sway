#!/bin/bash
set -euo pipefail

# Headless Sway + Sunshine Game Streaming Setup (Arch/KDE)

SWAY_CONFIG_DIR="$HOME/.config/sway-sunshine"
SUNSHINE_CONFIG_DIR="$HOME/.config/sunshine"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Headless Sway + Sunshine Installer ==="
echo ""

# Ensure user is in the 'input' group (required for virtual input devices)
if ! id -nG "$USER" | grep -qw input; then
    echo "Your user is not in the 'input' group (required for Sunshine virtual input)."
    read -rp "Add $USER to the input group now? [Y/n] " ADD_INPUT
    if [[ "${ADD_INPUT:-Y}" =~ ^[Yy]?$ ]]; then
        sudo usermod -aG input "$USER"
        echo "Added $USER to 'input' group. You must log out and back in for this to take effect."
        INPUT_GROUP_CHANGED=true
    else
        echo "Warning: Services may not work without 'input' group membership."
        INPUT_GROUP_CHANGED=false
    fi
else
    echo "User is in 'input' group"
    INPUT_GROUP_CHANGED=false
fi

# Install dependencies (--needed skips already-installed packages)
echo "Installing dependencies..."
sudo pacman -S --needed --noconfirm sway swaybg xdg-desktop-portal-wlr

# Check for Sunshine
if ! command -v sunshine &>/dev/null; then
    echo "Error: Sunshine not found. Install it with: paru -S sunshine"
    exit 1
fi
echo "Found Sunshine at: $(command -v sunshine)"

echo ""
echo "Installing config files..."

# Sway config and scripts
mkdir -p "$SWAY_CONFIG_DIR"
cp "$SCRIPT_DIR/sway-sunshine/config" "$SWAY_CONFIG_DIR/config"
cp "$SCRIPT_DIR/sway-sunshine/set-resolution.sh" "$SWAY_CONFIG_DIR/set-resolution.sh"
cp "$SCRIPT_DIR/sway-sunshine/reset-resolution.sh" "$SWAY_CONFIG_DIR/reset-resolution.sh"
cp "$SCRIPT_DIR/sway-sunshine/restore-default-sink.sh" "$SWAY_CONFIG_DIR/restore-default-sink.sh"
chmod +x "$SWAY_CONFIG_DIR"/*.sh

# Sunshine config
mkdir -p "$SUNSHINE_CONFIG_DIR"
cp "$SCRIPT_DIR/sunshine/sunshine.conf" "$SUNSHINE_CONFIG_DIR/sunshine.conf"
cp "$SCRIPT_DIR/sunshine/apps.json" "$SUNSHINE_CONFIG_DIR/apps.json"
echo "Installed Sunshine config"

# Systemd services
mkdir -p "$SYSTEMD_DIR"
cp "$SCRIPT_DIR/systemd/sway-sunshine.service" "$SYSTEMD_DIR/sway-sunshine.service"
cp "$SCRIPT_DIR/systemd/sunshine-headless.service" "$SYSTEMD_DIR/sunshine-headless.service"
echo "Installed systemd services"

# PipeWire persistent null sink (survives Moonlight disconnect)
PIPEWIRE_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PIPEWIRE_DIR"
cp "$SCRIPT_DIR/pipewire/sunshine-null-sink.conf" "$PIPEWIRE_DIR/sunshine-null-sink.conf"
systemctl --user restart pipewire.service
echo "Installed PipeWire audio sink"

# Remove stale udev input isolation rule if present (it breaks headless Sway input)
if [ -f "/etc/udev/rules.d/85-sunshine-input-isolation.rules" ]; then
    sudo rm -f "/etc/udev/rules.d/85-sunshine-input-isolation.rules"
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=input
    echo "Removed stale input isolation udev rule"
fi

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable sway-sunshine.service
systemctl --user enable sunshine-headless.service
systemctl --user mask sunshine.service 2>/dev/null || true
systemctl --user mask app-dev.lizardbyte.app.Sunshine.service 2>/dev/null || true

echo ""
echo "=== Installation complete ==="
echo ""
echo "To check status:"
echo "  systemctl --user status sway-sunshine sunshine-headless"
echo ""
echo "Pair with Moonlight at: https://$(hostname):47990"
echo ""

if [ "$INPUT_GROUP_CHANGED" = true ]; then
    echo "NOTE: You must log out and back in before starting services"
    echo "      (the 'input' group change requires a new login session)"
    echo ""
    echo "After re-login, run:"
    echo "  systemctl --user start sway-sunshine.service"
else
    read -rp "Start the services now? [Y/n] " START
    if [[ "${START:-Y}" =~ ^[Yy]?$ ]]; then
        systemctl --user start sway-sunshine.service
        echo "Services started. Open Moonlight to connect."
    fi
fi
