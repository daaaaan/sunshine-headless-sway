# Headless Sway + Sunshine Game Streaming

Stream games from a headless Sway session using [Sunshine](https://github.com/LizardByte/Sunshine) and [Moonlight](https://moonlight-stream.org/), without disrupting your main desktop session.

This setup runs a separate headless Wayland compositor (Sway) dedicated to game streaming. Your primary desktop (GNOME, KDE, etc.) continues running normally — audio, display, and input are fully isolated.

## Why headless?

- Stream games without taking over your main display
- Dynamic resolution matching — the headless output adapts to your Moonlight client
- Game audio routes only to the stream, host audio is unaffected
- Works with NVIDIA GPUs using NVENC hardware encoding

## Requirements

- **OS**: Linux with systemd user services (tested on Ubuntu 25.10)
- **GPU**: NVIDIA with proprietary drivers (for NVENC)
- **Packages**:
  ```
  sway swaybg sunshine pipewire wireplumber xdg-desktop-portal-wlr
  ```
- **Client**: [Moonlight](https://moonlight-stream.org/) on any device

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
│  └─ Video → wlr-screencopy → NVENC → Moonlight     │
└─────────────────────────────────────────────────────┘
```

## Setup

### 1. Install dependencies

```bash
sudo apt install sway swaybg xdg-desktop-portal-wlr
```

Install Sunshine from [LizardByte releases](https://github.com/LizardByte/Sunshine/releases) or as an AppImage.

### 2. Create the Sway config

```bash
mkdir -p ~/.config/sway-sunshine
```

Copy [`sway-sunshine/config`](sway-sunshine/config) to `~/.config/sway-sunshine/config`.

### 3. Create resolution scripts

Copy [`sway-sunshine/set-resolution.sh`](sway-sunshine/set-resolution.sh) and [`sway-sunshine/reset-resolution.sh`](sway-sunshine/reset-resolution.sh) to `~/.config/sway-sunshine/` and make them executable:

```bash
chmod +x ~/.config/sway-sunshine/set-resolution.sh
chmod +x ~/.config/sway-sunshine/reset-resolution.sh
```

These scripts dynamically match the headless output resolution to whatever your Moonlight client requests.

### 4. Install systemd services

Copy both service files to `~/.config/systemd/user/`:

```bash
cp systemd/sway-sunshine.service ~/.config/systemd/user/
cp systemd/sunshine-headless.service ~/.config/systemd/user/
```

**Important**: Edit `sunshine-headless.service` to set the correct `ExecStart` path for your Sunshine installation.

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now sway-sunshine.service
systemctl --user enable --now sunshine-headless.service
```

### 5. Configure Sunshine

Copy [`sunshine/sunshine.conf`](sunshine/sunshine.conf) to `~/.config/sunshine/sunshine.conf`.

The key setting is `sink = sink-sunshine-stereo` which tells Sunshine to capture audio from its own virtual sink without changing your system default.

### 6. Configure apps

Copy [`sunshine/apps.json`](sunshine/apps.json) to `~/.config/sunshine/apps.json`.

To add your own Steam games, find the app ID on [SteamDB](https://steamdb.info/) and add an entry:

```json
{
  "name": "Game Name",
  "detached": [
    "swaymsg exec 'steam steam://rungameid/APP_ID'"
  ],
  "prep-cmd": [
    {
      "do": "/home/YOUR_USER/.config/sway-sunshine/set-resolution.sh",
      "undo": ""
    }
  ]
}
```

### 7. Pair with Moonlight

Open Moonlight on your client device, find your host (it advertises via Avahi/mDNS), and pair using the PIN shown in Sunshine's web UI at `https://YOUR_HOST:47990`.

## Configuration details

### NVIDIA + headless Sway renderer

Use `WLR_RENDERER=gles2` in the Sway service. The Vulkan renderer has format modifier incompatibilities with NVIDIA's headless backend that cause frame capture failures.

### Audio isolation

The setup routes game audio exclusively to the Moonlight stream:

- `PULSE_SINK=sink-sunshine-stereo` is set in the Sway service environment, so any app launched in the headless session outputs to Sunshine's virtual sink
- `sink = sink-sunshine-stereo` in `sunshine.conf` tells Sunshine to capture from that sink directly, without changing the system default
- Your main desktop audio continues through your normal output device

### Dynamic resolution

When a Moonlight client connects, Sunshine runs `set-resolution.sh` as a prep command. This uses the `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS` environment variables to resize the headless output to match the client exactly. On disconnect, `reset-resolution.sh` reverts to 1080p.

### Wayland display numbering

The headless Sway session typically gets `wayland-1` (assuming your main desktop is `wayland-0`). If your system differs, update `WAYLAND_DISPLAY` in `sunshine-headless.service` accordingly. Check with:

```bash
ls /run/user/$(id -u)/wayland-*
```

### IPC socket

Sway creates its IPC socket at the path specified by `SWAYSOCK`. The service cleans up stale sockets on restart via `ExecStartPre`. All `swaymsg` commands in the apps and scripts reference this socket explicitly.

## Troubleshooting

### Blank display / error code -1

- Check `~/.config/sunshine/sunshine.log` for `Frame capture failed`
- Ensure `WLR_RENDERER=gles2` is set (not `vulkan`)
- Verify Sunshine is connecting to the correct Wayland display

### No input / can't control games

- The `xdg-desktop-portal-wlr` package must be installed for Sway's portal integration
- Check that `/dev/uinput` is accessible to your user (Sunshine's udev rules should handle this)

### Games don't launch

- Verify the Sway IPC socket exists: `ls -la /run/user/$(id -u)/sway-sunshine.sock`
- Test manually: `SWAYSOCK=/run/user/1000/sway-sunshine.sock swaymsg -t get_tree`
- If the socket is stale after a restart, the `ExecStartPre` cleanup in the service should handle it

### Audio bleeds to host

- Verify `sink = sink-sunshine-stereo` is in `sunshine.conf`
- Check `PULSE_SINK=sink-sunshine-stereo` is in `sway-sunshine.service`
- Confirm your default sink: `wpctl status | grep "Default Configured"`

### UPnP port mapping failures

These errors (`Failed to map UDP/TCP`) are harmless if you're connecting over LAN or a VPN like Tailscale. They only matter for WAN connections through your router.

## File structure

```
~/.config/
├── sway-sunshine/
│   ├── config                  # Headless Sway compositor config
│   ├── set-resolution.sh       # Dynamic resolution on connect
│   └── reset-resolution.sh     # Reset resolution on disconnect
├── sunshine/
│   ├── sunshine.conf           # Sunshine server config
│   └── apps.json               # Game/app entries for Moonlight
└── systemd/user/
    ├── sway-sunshine.service   # Headless Sway compositor service
    └── sunshine-headless.service # Sunshine streaming service
```

## License

MIT
