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

# Detect package manager
install_pkg() {
    if command -v pacman &>/dev/null; then
        sudo pacman -S --needed --noconfirm "$@"
    elif command -v apt &>/dev/null; then
        sudo apt install -y "$@"
    else
        echo "Error: No supported package manager found (pacman or apt)"
        exit 1
    fi
}

is_pkg_installed() {
    if command -v pacman &>/dev/null; then
        pacman -Qi "$1" &>/dev/null
    elif command -v dpkg &>/dev/null; then
        dpkg -s "$1" &>/dev/null 2>&1
    else
        return 1
    fi
}

# Install dependencies
for cmd in sway swaybg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing sway and swaybg..."
        install_pkg sway swaybg
        break
    fi
done

if ! is_pkg_installed xdg-desktop-portal-wlr; then
    echo "Installing xdg-desktop-portal-wlr..."
    install_pkg xdg-desktop-portal-wlr
fi

# Detect desktop environment
detect_de() {
    local de="${XDG_CURRENT_DESKTOP:-}"
    de="${de,,}"  # lowercase

    if [[ "$de" == *"gnome"* ]] || [[ "$de" == *"unity"* ]] || [[ "$de" == *"budgie"* ]]; then
        echo "gnome"
    elif [[ "$de" == *"kde"* ]] || [[ "$de" == *"plasma"* ]]; then
        echo "kde"
    elif command -v mutter &>/dev/null; then
        echo "gnome"
    elif command -v kwin_wayland &>/dev/null || command -v kwin_x11 &>/dev/null; then
        echo "kde"
    else
        echo "unknown"
    fi
}

DETECTED_DE=$(detect_de)

echo ""
if [ "$DETECTED_DE" = "gnome" ]; then
    echo "Detected desktop environment: GNOME"
    echo "  → Will use mutter-device-ignore for input isolation"
elif [ "$DETECTED_DE" = "kde" ]; then
    echo "Detected desktop environment: KDE Plasma"
    echo "  → Will strip ID_INPUT tags for input isolation"
else
    echo "Could not auto-detect desktop environment."
    echo ""
    echo "Input isolation method depends on your desktop:"
    echo "  1) GNOME  — uses mutter-device-ignore (targeted, GNOME-only)"
    echo "  2) KDE    — strips ID_INPUT tags (works with KWin and other compositors)"
    echo ""
    read -rp "Select your desktop [1/2]: " DE_CHOICE
    case "$DE_CHOICE" in
        1) DETECTED_DE="gnome" ;;
        2) DETECTED_DE="kde" ;;
        *)
            echo "Invalid choice. Defaulting to GNOME method (safer — targets Mutter specifically, doesn't break libinput)."
            DETECTED_DE="gnome"
            ;;
    esac
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

# Detect UID for socket paths
USER_ID=$(id -u)
SOCKET_PATH="/run/user/$USER_ID/sway-sunshine.sock"

# Check for stale sway-sunshine session and stop it gracefully
PID_FILE="/run/user/$USER_ID/sway-sunshine.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    WAYLAND_SOCKET=""

    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Found running sway-sunshine session (PID $OLD_PID), stopping..."

        # Scan Wayland socket BEFORE killing — /proc/PID/fd disappears after
        WAYLAND_DIR="/run/user/$USER_ID"
        WAYLAND_SOCKET=$(ls -l /proc/$OLD_PID/fd 2>/dev/null | grep "$WAYLAND_DIR/wayland-" | head -1 | sed 's|.*-> \(.*\)|\1|' || true)

        kill -INT "$OLD_PID"
        for i in $(seq 1 10); do
            kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "Session did not stop gracefully, force killing..."
            kill -9 "$OLD_PID" 2>/dev/null
            sleep 1
        fi
    else
        echo "Found stale PID file (process $OLD_PID not running)"
    fi

    rm -f "$PID_FILE" "$SOCKET_PATH"

    # Remove Wayland socket — use /proc scan result, fall back to filesystem
    WAYLAND_DIR="/run/user/$USER_ID"
    if [ -n "$WAYLAND_SOCKET" ] && [ -e "$WAYLAND_SOCKET" ]; then
        rm -f "$WAYLAND_SOCKET"
        echo "Removed sway-sunshine wayland socket: $WAYLAND_SOCKET"
    else
        # Fallback: remove highest-numbered wayland socket if multiple exist
        WAYLAND_COUNT=$( (ls "$WAYLAND_DIR"/wayland-* 2>/dev/null || true) | grep -v lock | wc -l)
        if [ "$WAYLAND_COUNT" -ge 2 ]; then
            HIGH=$( (ls "$WAYLAND_DIR"/wayland-* 2>/dev/null || true) | grep -v lock | sort | tail -1)
            rm -f "$HIGH"
            echo "Removed stale wayland socket: $(basename "$HIGH")"
        fi
    fi

    echo "Previous session stopped."

    # Restart Sunshine to capture from the new Sway session
    echo "Restarting Sunshine for new Sway session..."
    systemctl --user restart sunshine-headless.service 2>/dev/null || true
    sleep 1
fi

# Detect Wayland display for the headless session
# Strategy: prefer the value already set in the installed service file (avoids
# conflicts when the user has already started sway-sunshine manually), fall back
# to auto-detection on fresh installs.
HEADLESS_DISPLAY=""

# 1. Check if the installed service file already has WAYLAND_DISPLAY set
INSTALLED_SERVICE="$SYSTEMD_DIR/sway-sunshine.service"
if [ -f "$INSTALLED_SERVICE" ]; then
    EXISTING_DISPLAY=$(grep '^Environment=WAYLAND_DISPLAY=' "$INSTALLED_SERVICE" | head -1 | sed 's|^Environment=WAYLAND_DISPLAY=||')
    if [ -n "$EXISTING_DISPLAY" ]; then
        HEADLESS_DISPLAY="$EXISTING_DISPLAY"
        echo "Found existing WAYLAND_DISPLAY=$HEADLESS_DISPLAY in installed service file — using that value"
    fi
fi

# 2. Fall back to auto-detection if no existing display was found
if [ -z "$HEADLESS_DISPLAY" ]; then
    MAIN_WAYLAND=$(ls /run/user/$(id -u)/wayland-* 2>/dev/null | grep -v lock | sort | tail -1 | xargs basename)
    if [ "$MAIN_WAYLAND" = "wayland-0" ]; then
        HEADLESS_DISPLAY="wayland-1"
    else
        HEADLESS_DISPLAY="wayland-$((${MAIN_WAYLAND##wayland-} + 1))"
    fi
    echo "Auto-detected main display: $MAIN_WAYLAND, headless will be: $HEADLESS_DISPLAY"
fi

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
cp "$SCRIPT_DIR/sway-sunshine/restore-default-sink.sh" "$SWAY_CONFIG_DIR/restore-default-sink.sh"
chmod +x "$SWAY_CONFIG_DIR/set-resolution.sh"
chmod +x "$SWAY_CONFIG_DIR/reset-resolution.sh"
chmod +x "$SWAY_CONFIG_DIR/restore-default-sink.sh"

# Steam scripts (template WAYLAND_DISPLAY for non-default display numbers)
sed "s|WAYLAND_DISPLAY=\"wayland-1\"|WAYLAND_DISPLAY=\"$HEADLESS_DISPLAY\"|" \
    "$SCRIPT_DIR/sway-sunshine/start-steam-game.sh" > "$SWAY_CONFIG_DIR/start-steam-game.sh"
cp "$SCRIPT_DIR/sway-sunshine/stop-steam-game.sh" "$SWAY_CONFIG_DIR/stop-steam-game.sh"
chmod +x "$SWAY_CONFIG_DIR/start-steam-game.sh"
chmod +x "$SWAY_CONFIG_DIR/stop-steam-game.sh"

# Lutris scripts (template WAYLAND_DISPLAY for non-default display numbers)
sed "s|WAYLAND_DISPLAY=\"wayland-1\"|WAYLAND_DISPLAY=\"$HEADLESS_DISPLAY\"|" \
    "$SCRIPT_DIR/sway-sunshine/start-lutris-game.sh" > "$SWAY_CONFIG_DIR/start-lutris-game.sh"
cp "$SCRIPT_DIR/sway-sunshine/stop-lutris-game.sh" "$SWAY_CONFIG_DIR/stop-lutris-game.sh"
chmod +x "$SWAY_CONFIG_DIR/start-lutris-game.sh"
chmod +x "$SWAY_CONFIG_DIR/stop-lutris-game.sh"

# Sway wrapper (tracks session PID for graceful shutdown)
cp "$SCRIPT_DIR/sway-sunshine/sway-wrapper.sh" "$SWAY_CONFIG_DIR/sway-wrapper.sh"
chmod +x "$SWAY_CONFIG_DIR/sway-wrapper.sh"

# Sunshine config (always copy from template)
mkdir -p "$SUNSHINE_CONFIG_DIR"
cp "$SCRIPT_DIR/sunshine/sunshine.conf" "$SUNSHINE_CONFIG_DIR/sunshine.conf"
echo "Installed sunshine.conf"

# Apps config (only if not already present)
if [ ! -f "$SUNSHINE_CONFIG_DIR/apps.json" ]; then
    sed "s|/home/YOUR_USER/|$HOME/|g" \
        "$SCRIPT_DIR/sunshine/apps.json" > "$SUNSHINE_CONFIG_DIR/apps.json"
    sed -i "s|/run/user/1000/|/run/user/$USER_ID/|g" "$SUNSHINE_CONFIG_DIR/apps.json"
    echo "Created apps.json"
else
    echo "apps.json already exists, running migration..."
    # Migrate old Steam entries from cmd-based to detached-based format
    python3 - "$SUNSHINE_CONFIG_DIR/apps.json" "$HOME" <<'PYEOF'
import json
import sys
import re
import base64

apps_json_path = sys.argv[1]
home_dir = sys.argv[2]
start_steam = f"{home_dir}/.config/sway-sunshine/start-steam-game.sh"
stop_steam = f"{home_dir}/.config/sway-sunshine/stop-steam-game.sh"
start_lutris = f"{home_dir}/.config/sway-sunshine/start-lutris-game.sh"
stop_lutris = f"{home_dir}/.config/sway-sunshine/stop-lutris-game.sh"

try:
    with open(apps_json_path, "r") as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"Warning: Could not parse {apps_json_path}: {e}")
    sys.exit(0)

apps = data.get("apps", [])
migrated = 0

def ensure_restore_default_sink(prep_cmds):
    """Add restore-default-sink.sh as first prep-cmd entry if missing."""
    has_restore = any(
        "restore-default-sink.sh" in entry.get("do", "")
        for entry in prep_cmds
    )
    if not has_restore:
        prep_cmds.insert(0, {"do": "$HOME/.config/sway-sunshine/restore-default-sink.sh", "undo": ""})
    return prep_cmds

def dedup_restore(prep_cmds):
    """Remove duplicate restore-default-sink entries, keeping only the first."""
    seen_restore = False
    cleaned = []
    for entry in prep_cmds:
        if "restore-default-sink.sh" in entry.get("do", ""):
            if seen_restore:
                continue
            seen_restore = True
        cleaned.append(entry)
    return cleaned

def migrate_prep_undo(prep_cmds, stop_script):
    """Update set-resolution undo from reset-resolution.sh to stop-<type>-game.sh."""
    for entry in prep_cmds:
        if "set-resolution.sh" in entry.get("do", "") and "reset-resolution.sh" in entry.get("undo", ""):
            entry["undo"] = stop_script
    return prep_cmds

# --- Steam migration ---
for app in apps:
    cmd = app.get("cmd", "")
    detached = app.get("detached", [])

    # Only migrate entries that use steam://run/ format
    match = re.match(r'^steam\s+steam://run/(\d+)$', cmd.strip())
    if not match:
        continue

    appid = match.group(1)
    print(f"  Migrating: {app.get('name', 'unnamed')} (appid: {appid})")

    # Build the new detached command
    app["detached"] = [f"{start_steam} {appid}"]
    app["cmd"] = ""

    # Update prep-cmd
    prep_cmds = app.get("prep-cmd", [])
    migrate_prep_undo(prep_cmds, stop_steam)
    app["prep-cmd"] = dedup_restore(prep_cmds)

    # Ensure image-path exists for migrated entries
    if "image-path" not in app:
        app["image-path"] = "steam.png"

    migrated += 1

# --- Lutris migration ---
for app in apps:
    cmd = app.get("cmd", "")

    # Only migrate entries that use lutristosunshine-launch-app.sh
    if "lutristosunshine-launch-app.sh" not in cmd:
        continue

    # Extract base64 from the cmd:
    # lutristosunshine-launch-app.sh cmd <timeout> <base64>
    parts = cmd.strip().split()
    if len(parts) < 4:
        print(f"  Skipping: {app.get('name', 'unnamed')} (invalid lutris cmd format)")
        continue

    base64_cmd = parts[3]

    # Decode the base64 command
    try:
        decoded = base64.b64decode(base64_cmd).decode("utf-8")
    except Exception as e:
        print(f"  Skipping: {app.get('name', 'unnamed')} (base64 decode failed: {e})")
        continue

    # Extract game ID from lutris:rungameid/<id>
    id_match = re.search(r'lutris:rungameid/(\d+)', decoded)
    if not id_match:
        print(f"  Skipping: {app.get('name', 'unnamed')} (no game ID found in decoded command: {decoded})")
        continue

    game_id = id_match.group(1)
    print(f"  Migrating: {app.get('name', 'unnamed')} (game_id: {game_id})")

    # Build the new detached command
    app["detached"] = [f"{start_lutris} {game_id}"]
    app["cmd"] = ""

    # Update prep-cmd
    prep_cmds = app.get("prep-cmd", [])
    migrate_prep_undo(prep_cmds, stop_lutris)
    app["prep-cmd"] = ensure_restore_default_sink(prep_cmds)
    app["prep-cmd"] = dedup_restore(app["prep-cmd"])

    # Set image-path
    if "image-path" not in app:
        app["image-path"] = "lutris.png"

    migrated += 1

if migrated > 0:
    with open(apps_json_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"  Migrated {migrated} entry(ies) to detached format")
else:
    print("  No entries need migration")
PYEOF
fi

# Systemd services
mkdir -p "$SYSTEMD_DIR"

sed -e "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    -e "s|WAYLAND_DISPLAY=wayland-1|WAYLAND_DISPLAY=$HEADLESS_DISPLAY|g" \
    "$SCRIPT_DIR/systemd/sway-sunshine.service" > "$SYSTEMD_DIR/sway-sunshine.service"

sed -e "s|/run/user/1000/|/run/user/$USER_ID/|g" \
    -e "s|WAYLAND_DISPLAY=wayland-1|WAYLAND_DISPLAY=$HEADLESS_DISPLAY|g" \
    -e "s|ExecStart=.*|ExecStart=$SUNSHINE_PATH|g" \
    "$SCRIPT_DIR/systemd/sunshine-headless.service" > "$SYSTEMD_DIR/sunshine-headless.service"

# PipeWire persistent null sink (survives Moonlight disconnect)
PIPEWIRE_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PIPEWIRE_DIR"
cp "$SCRIPT_DIR/pipewire/sunshine-null-sink.conf" "$PIPEWIRE_DIR/sunshine-null-sink.conf"
echo "Installed PipeWire persistent audio sink"

# udev rule: install DE-appropriate input isolation rule
# NOTE: This requires sudo. Running it manually ensures you control the action.
UDEV_RULE="85-sunshine-input-isolation.rules"
if [ "$DETECTED_DE" = "gnome" ]; then
    UDEV_SRC="$SCRIPT_DIR/udev/85-sunshine-input-isolation-gnome.rules"
    echo "Installed GNOME input isolation rule (mutter-device-ignore)"
else
    UDEV_SRC="$SCRIPT_DIR/udev/85-sunshine-input-isolation-kde.rules"
    echo "Installed KDE input isolation rule (ID_INPUT stripping)"
fi

echo ""
echo "To install the udev rule (requires sudo):"
echo "  sudo cp \"$UDEV_SRC\" \"/etc/udev/rules.d/$UDEV_RULE\""
echo "  sudo udevadm control --reload-rules"
echo ""

echo "Installed systemd services"

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable sway-sunshine.service
systemctl --user enable sunshine-headless.service

echo ""

# Restart Sunshine to pick up new config and capture from current Sway session
echo "Restarting Sunshine..."
systemctl --user restart sunshine-headless.service 2>/dev/null || true
sleep 1

echo "=== Installation complete ==="
echo ""
echo "Desktop environment: $([ "$DETECTED_DE" = "gnome" ] && echo "GNOME" || echo "KDE/Other")"
echo "Wayland display: $HEADLESS_DISPLAY"
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
