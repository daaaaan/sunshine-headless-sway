# Headless Sway + Sunshine Game Streaming

> **DISCLAIMER**: This is provided as-is with absolutely no warranty or guarantee. Use at your own risk. This may break your system, eat your configs, set your GPU on fire, or summon an elder god. The author(s) take no responsibility for anything that happens as a result of using this software. You have been warned.

![Architecture Diagram](diagram.svg)

Stream games from a headless Sway session using [Sunshine](https://github.com/LizardByte/Sunshine) and [Moonlight](https://moonlight-stream.org/), without disrupting your main desktop session.

This setup runs a separate headless Wayland compositor (Sway) dedicated to game streaming. Your primary desktop (GNOME, KDE, etc.) continues running normally — audio, display, and input are fully isolated.

## Why headless?

- Stream games without taking over your main display
- Dynamic resolution matching — the headless output adapts to your Moonlight client
- Game audio routes only to the stream, host audio is unaffected
- Works with NVIDIA GPUs using NVENC hardware encoding
- Minimal overhead when idle (~420MB RAM, negligible CPU)

## Requirements

- **OS**: Linux with systemd user services (tested on CachyOS/Arch and Ubuntu 25.10)
- **GPU**: Any modern GPU with hardware encoding support (NVENC for NVIDIA, VCN for AMD)
- **Packages**: `sway`, `swaybg`, `pipewire`, `wireplumber`, `xdg-desktop-portal-wlr`
- **Sunshine**: [LizardByte Sunshine](https://github.com/LizardByte/Sunshine/releases) v2026.226+ (deb for Ubuntu, `sunshine` AUR package for Arch)
- **Client**: [Moonlight](https://moonlight-stream.org/) on any device

## Quick install

```bash
git clone https://github.com/daaaaan/sunshine-headless-sway.git
cd sunshine-headless-sway
./install.sh
```

The install script will:
- Install missing dependencies (`sway`, `swaybg`, `xdg-desktop-portal-wlr`) via pacman or apt
- Auto-detect your desktop environment (GNOME or KDE) for input isolation
- Auto-detect your Sunshine installation path
- Detect the correct Wayland display number and user ID
- Template all config files with your system's paths
- Install and enable the systemd services
- Preserve any existing Sunshine config you already have

## Manual setup

If you prefer to install manually, see the [manual setup guide](#manual-setup-guide) below.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Main Desktop (GNOME/KDE)          wayland-0        │
│  └─ Normal apps, browser, etc.                      │
│  └─ Audio → your speakers/headphones                │
├─────────────────────────────────────────────────────┤
│  Headless Sway                     wayland-1        │
│  └─ Games launched via Sunshine                     │
│  └─ Audio → sink-sunshine-stereo → Moonlight stream │
│  └─ Video → wlr-screencopy → hardware encoder → Moonlight │
└─────────────────────────────────────────────────────┘
```

Two systemd user services manage the stack:

1. **`sway-sunshine.service`** — runs a headless Sway compositor with no physical display
2. **`sunshine-headless.service`** — runs Sunshine pointed at the headless Sway session

## Adding games

Edit `~/.config/sunshine/apps.json` to add games. The install script provides templates for Steam and Lutris. Find Steam app IDs on [SteamDB](https://steamdb.info/).

### Steam games

```json
{
  "name": "Game Name",
  "detached": [
    "~/.config/sway-sunshine/start-steam-game.sh <appid>"
  ],
  "prep-cmd": [
    {"do": "~/.config/sway-sunshine/restore-default-sink.sh", "undo": ""},
    {"do": "~/.config/sway-sunshine/set-resolution.sh", "undo": "~/.config/sway-sunshine/stop-steam-game.sh"}
  ]
}
```

### Lutris games

```json
{
  "name": "Game Name (Lutris)",
  "detached": [
    "~/.config/sway-sunshine/start-lutris-game.sh <slug_or_id>"
  ],
  "prep-cmd": [
    {"do": "~/.config/sway-sunshine/restore-default-sink.sh", "undo": ""},
    {"do": "~/.config/sway-sunshine/set-resolution.sh", "undo": "~/.config/sway-sunshine/stop-lutris-game.sh"}
  ]
}
```

### Bulk import with LutrisToSunshine

For bulk importing from multiple launchers, this repo bundles [LutrisToSunshine](https://github.com/Arbitrate3280/LutrisToSunshine) ([MIT](./LutrisToSunshine/LICENSE)) — a CLI tool that scans installed game launchers and imports games into Sunshine with optional cover art from SteamGridDB.

**Supported launchers:** Lutris (native + Flatpak), Heroic (Legendary, GOG, Nile, Sideload — native + Flatpak), Bottles, Steam, Faugus, Ryubing, RetroArch, Eden.

```bash
cd LutrisToSunshine
pip install -r requirements.txt
python3 lutristosunshine.py --all --cover --force
```

Use `--all` to skip the selection prompt, `--cover` to download SteamGridDB artwork, and `--force` to overwrite existing entries. The tool detects whether Sunshine or Apollo is running and adds games via the API.

> **Tip:** After importing, run `./install.sh` to auto-migrate any `lutristosunshine-launch-app.sh` entries to use the repo's `start-lutris-game.sh` scripts.

Restart Sunshine after editing: `systemctl --user restart sunshine-headless.service`

## How it works

### Headless Sway renderer

The Sway service uses `WLR_RENDERER=gles2` by default for maximum compatibility. For better rendering performance on modern wlroots versions (0.20+), you can try `WLR_RENDERER=vulkan`.

> **Note:** wlroots 0.19.3 has a known bug with the Vulkan renderer on the `headless` backend causing XR24 format errors. Use gles2 if you're on wlroots 0.19.3. The stream may work despite these errors if frame capture succeeds.

### Audio isolation

Game audio is routed exclusively to the Moonlight stream without touching your host audio:

- A persistent PipeWire null sink (`sink-sunshine-stereo`) is created via config drop-in — it always exists, even when Moonlight is disconnected or backgrounded
- `PULSE_SINK=sink-sunshine-stereo` is set in the Sway service environment, so apps launched in the headless session output to this sink
- `audio_sink = sink-sunshine-stereo` in `sunshine.conf` tells Sunshine to capture from that sink
- `restore-default-sink.sh` runs as a prep command to prevent Sunshine from hijacking your host's default audio sink — it detects the change and restores it within seconds
- When Moonlight is backgrounded, game audio stays in the persistent null sink (silent) instead of reverting to your host speakers
- Your main desktop audio continues through your normal output device

### Dynamic resolution

When a Moonlight client connects, Sunshine runs `set-resolution.sh` as a prep command. This uses `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS` environment variables to resize the headless output to match the client exactly. On disconnect, `reset-resolution.sh` reverts to 1080p.

### Multi-GPU setup

This setup works with both single-GPU and dual-GPU systems. On multi-GPU setups, two environment variables control GPU selection:

- **`WLR_DRM_DEVICES`** in `sway-sunshine.service` — tells Sway which render node to use for rendering
- **`adapter_name`** in `sunshine.conf` — tells Sunshine which render node to use for importing frames via DMA-BUF

Both should point to the same GPU (the one where Sway renders). On this specific setup, Sway renders on the NVIDIA GPU (`renderD129`) and `adapter_name` in sunshine.conf also points to `renderD129`. The encoding backend (NVENC on NVIDIA or VCN on AMD) is determined by Vulkan auto-selection unless `VK_ICD_FILENAMES` is explicitly set. On single-GPU systems, the defaults are usually correct. On multi-GPU systems, verify with:

```bash
ls -la /dev/dri/renderD*
ls -la /sys/class/drm/card*/device/vendor  # 0x10de = NVIDIA, 0x1002 = AMD
```

### Wayland display numbering

The headless Sway session typically gets `wayland-1` (assuming your main desktop is `wayland-0`). The install script detects this automatically. To check manually:

```bash
ls /run/user/$(id -u)/wayland-*
```

### IPC socket

Sway creates its IPC socket at the path specified by `SWAYSOCK` (`/run/user/<uid>/sway-sunshine.sock`). The service cleans up stale sockets on restart via `ExecStartPre`. All `swaymsg` commands in the apps and scripts reference this socket explicitly.

## Troubleshooting

### Blank display / error code -1

- Check `~/.config/sunshine/sunshine.log` for `Frame capture failed`
- Verify `WLR_DRM_DEVICES` in `sway-sunshine.service` points to the correct render node
- Verify `adapter_name` in `sunshine.conf` matches the render node where Sway renders
- Ensure Sunshine is connecting to the correct Wayland display

### Input isolation

Input is fully isolated between your desktop and the streaming session. Sunshine creates virtual input devices (vendor `0xBEEF`, product `0xDEAD`) that must be hidden from your host desktop while remaining accessible to the headless Sway session.

The install script **auto-detects your desktop environment** and installs the appropriate udev rule. Both approaches install to `/etc/udev/rules.d/85-sunshine-input-isolation.rules`.

#### GNOME (Mutter)

Uses the `mutter-device-ignore` property — a targeted GNOME-specific mechanism that tells Mutter to skip specific devices while leaving them visible to other consumers:

```udev
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{id/vendor}=="beef", ATTRS{id/product}=="dead", ENV{mutter-device-ignore}="1"
```

#### KDE (KWin)

KWin has no equivalent to `mutter-device-ignore`. Instead, the udev rule strips `ID_INPUT` tags so KWin never discovers the devices as inputs:

```udev
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{id/vendor}=="beef", ATTRS{id/product}=="dead", ENV{ID_INPUT}="", ENV{ID_INPUT_KEYBOARD}="", ENV{ID_INPUT_MOUSE}="", ENV{ID_INPUT_TOUCHPAD}=""
```

> **Note**: The KDE method also works for GNOME and other compositors, but is more aggressive — it hides the devices from *all* desktop tools (e.g., Settings panels). The `mutter-device-ignore` method is preferred for GNOME since it's more targeted.

#### How isolation works

- The **udev rule** prevents the host compositor from claiming Sunshine's virtual inputs (method varies by DE, see above)
- The headless Sway uses `WLR_BACKENDS=headless,libinput` with `LIBSEAT_BACKEND=noop` and runs under the `input` group via `sg` to access input devices without a logind seat
- The **Sway config** disables all physical host devices and only enables Sunshine's passthrough devices, so your physical keyboard and mouse don't leak into the streaming session
- **KDE Plasma workaround**: `KWIN_DRM_NO_DIRECT_SCANOUT=1` and `KWIN_FORCE_SW_CURSOR=1` are set in `sunshine-headless.service` to prevent KWin from interfering with the headless session
- Gamepads are read directly by Steam via evdev, bypassing the compositor entirely

#### Switching DE method manually

If you switch desktop environments, reinstall the appropriate rule:

```bash
# For GNOME
sudo cp udev/85-sunshine-input-isolation-gnome.rules /etc/udev/rules.d/85-sunshine-input-isolation.rules

# For KDE
sudo cp udev/85-sunshine-input-isolation-kde.rules /etc/udev/rules.d/85-sunshine-input-isolation.rules

# Reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input
```

### No input / can't control games

- The `xdg-desktop-portal-wlr` package must be installed
- Check that `/dev/uinput` is accessible to your user (Sunshine's udev rules should handle this)
- Verify the libinput backend is active: `SWAYSOCK=/run/user/$(id -u)/sway-sunshine.sock swaymsg -t get_inputs` should show Sunshine passthrough devices with `events: enabled`

### Games don't launch

- Verify the Sway IPC socket exists: `ls -la /run/user/$(id -u)/sway-sunshine.sock`
- Test manually: `SWAYSOCK=/run/user/$(id -u)/sway-sunshine.sock swaymsg -t get_tree`
- If the socket is stale after a restart, the `ExecStartPre` cleanup in the service handles it

### Audio bleeds to host

- Verify `audio_sink = sink-sunshine-stereo` is in `~/.config/sunshine/sunshine.conf`
- Check `PULSE_SINK=sink-sunshine-stereo` is in `sway-sunshine.service`
- Verify the `restore-default-sink.sh` prep command is in `apps.json` — without it, Sunshine sets `sink-sunshine-stereo` as the system-wide default, routing all host audio into the stream
- Confirm your default sink after connecting: `wpctl status | grep '\*'`

### UPnP port mapping failures

These errors (`Failed to map UDP/TCP`) are harmless if you're connecting over LAN or a VPN like Tailscale. They only matter for WAN connections through your router.

## Manual setup guide

If you'd rather not use the install script:

### 1. Install dependencies

**Arch / CachyOS:**
```bash
sudo pacman -S sway swaybg xdg-desktop-portal-wlr
```

**Ubuntu / Debian:**
```bash
sudo apt install sway swaybg xdg-desktop-portal-wlr
```

### 2. Copy config files

```bash
# Sway config and scripts
mkdir -p ~/.config/sway-sunshine
cp sway-sunshine/config ~/.config/sway-sunshine/
cp sway-sunshine/set-resolution.sh ~/.config/sway-sunshine/
cp sway-sunshine/reset-resolution.sh ~/.config/sway-sunshine/
chmod +x ~/.config/sway-sunshine/*.sh

# Sunshine config
cp sunshine/sunshine.conf ~/.config/sunshine/sunshine.conf
cp sunshine/apps.json ~/.config/sunshine/apps.json

# PipeWire persistent audio sink
mkdir -p ~/.config/pipewire/pipewire.conf.d
cp pipewire/sunshine-null-sink.conf ~/.config/pipewire/pipewire.conf.d/
systemctl --user restart pipewire.service

# Systemd services
mkdir -p ~/.config/systemd/user
cp systemd/sway-sunshine.service ~/.config/systemd/user/
cp systemd/sunshine-headless.service ~/.config/systemd/user/
```

### 3. Edit paths

Update the following in the copied files to match your system:

- `sunshine-headless.service`: set `ExecStart` to your Sunshine path, `WAYLAND_DISPLAY` to your headless display
- `sway-sunshine.service`: update `/run/user/1000/` to `/run/user/$(id -u)/` if your UID isn't 1000, set `WLR_DRM_DEVICES` to the correct render node
- `sunshine.conf`: set `adapter_name` to match the render node in `WLR_DRM_DEVICES`
- `apps.json`: update `/home/YOUR_USER/` to your home directory
- `set-resolution.sh` / `reset-resolution.sh`: update the socket path if your UID isn't 1000

### 4. Enable and start

```bash
systemctl --user daemon-reload
systemctl --user enable --now sway-sunshine.service
systemctl --user enable --now sunshine-headless.service
```

### 5. Pair with Moonlight

Open Moonlight, find your host, and pair using the PIN at `https://YOUR_HOST:47990`.

## File structure

```
/etc/udev/rules.d/
└── 85-sunshine-input-isolation.rules  # Installed by install.sh (GNOME or KDE variant)

sunshine-headless-sway/
├── install.sh                  # One-command setup script
├── LutrisToSunshine/           # Bundled game importer (LutrisToSunshine)
├── ~/.config/
│   ├── pipewire/pipewire.conf.d/
│   │   └── sunshine-null-sink.conf # Persistent audio sink (survives disconnect)
│   ├── sway-sunshine/
│   │   ├── config                  # Headless Sway compositor config (input isolation)
│   │   ├── set-resolution.sh       # Dynamic resolution on connect
│   │   ├── reset-resolution.sh     # Reset resolution on disconnect
│   │   ├── restore-default-sink.sh # Prevents Sunshine from hijacking host audio
│   │   └── sway-wrapper.sh         # PID-tracking wrapper for sway service
│   ├── sunshine/
│   │   ├── sunshine.conf           # Sunshine server config
│   │   └── apps.json               # Game/app entries for Moonlight
│   └── systemd/user/
│       ├── sway-sunshine.service   # Headless Sway compositor service
│       └── sunshine-headless.service # Sunshine streaming service
```

## License

MIT — do whatever you want with it, but don't blame us if something breaks.
