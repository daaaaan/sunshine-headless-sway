# Virtual Display Setup for CachyOS + KDE Plasma

This documents the full setup for headless game streaming with Sunshine + Moonlight on a CachyOS KDE Plasma system with an NVIDIA GPU. The goal: when a Moonlight client connects, a virtual display is created at the client's native resolution, fully isolated from the main desktop.

## System Profile

| Component | Details |
|-----------|---------|
| OS | CachyOS (Arch-based), kernel 6.19.7-1-cachyos |
| Desktop | KDE Plasma on Wayland (`wayland-0`) |
| GPU | NVIDIA RTX 5090 (GB202), driver 595.45.04 |
| Displays | DP-2 (3840x2160@240Hz), HDMI-A-2 (3840x2160@30Hz) |
| Audio | PipeWire 1.6.2 with PulseAudio compatibility layer |
| Sunshine | v2025.924.154138 at `/usr/bin/sunshine` |
| Encoder | NVENC (hardware encoding via RTX 5090) |

## How It Works

Instead of streaming the main KDE desktop, a completely separate headless Sway compositor runs alongside it. This gives us:

- **Display isolation** — games render on a virtual output (`wayland-1`), the KDE desktop (`wayland-0`) is untouched
- **Audio isolation** — game audio routes to a PipeWire null sink captured by Sunshine; host audio is unaffected
- **Input isolation** — Sunshine's virtual keyboard/mouse (vendor `0xBEEF`, product `0xDEAD`) are only enabled in the headless Sway session via its config; KDE never sees them
- **Dynamic resolution** — each Moonlight client gets its native resolution/refresh rate applied to the virtual display automatically

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│  KDE Plasma (main desktop)              wayland-0        │
│  └─ Normal apps, browser, etc.                           │
│  └─ Audio → speakers/headphones                          │
│  └─ Input → physical keyboard/mouse                      │
├──────────────────────────────────────────────────────────┤
│  Headless Sway (streaming session)      wayland-1        │
│  └─ Games launched via Sunshine/Moonlight                │
│  └─ Audio → sink-sunshine-stereo → Moonlight stream      │
│  └─ Video → wlr-screencopy → NVENC → Moonlight stream   │
│  └─ Input → Sunshine virtual devices only                │
└──────────────────────────────────────────────────────────┘
```

Two systemd user services manage the stack:

1. **`sway-sunshine.service`** — headless Sway compositor with no physical display
2. **`sunshine-headless.service`** — Sunshine instance pointed at the headless session

### Component Details

**Capture pipeline:** Sunshine uses `capture = wlr` (wlr-screencopy protocol) to grab frames from the headless Sway compositor. These frames are then encoded via NVENC on the RTX 5090 and streamed to Moonlight. The `wlr` capture method is independent of the GPU encoder — it captures the compositor output, NVENC handles the encoding.

**Audio pipeline:** A persistent PipeWire null sink (`sink-sunshine-stereo`) is created via a config drop-in at `~/.config/pipewire/pipewire.conf.d/sunshine-null-sink.conf`. The headless Sway session sets `PULSE_SINK=sink-sunshine-stereo` so all apps in that session output to this sink. Sunshine captures from the same sink. A `restore-default-sink.sh` prep command prevents Sunshine from hijacking the host's default audio output.

**Input isolation:** The headless Sway config disables all physical devices (`input * events disabled`) and selectively enables only Sunshine's virtual passthrough devices. The session uses `WLR_BACKENDS=headless,libinput` with `LIBSEAT_BACKEND=noop` and runs under the `input` group (via `sg input`) to access input devices without a logind seat. No udev rules are needed — a stale udev rule that strips `ID_INPUT` tags will actually *break* input by hiding the devices from Sway's libinput backend.

**Dynamic resolution:** When a Moonlight client connects, Sunshine runs `set-resolution.sh` as a prep command. This reads `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, and `SUNSHINE_CLIENT_FPS` environment variables and resizes the headless Sway output to match. On disconnect, `reset-resolution.sh` reverts to 1920x1080. This means a 4K TV, a 1440p monitor, or a phone each get their native resolution automatically.

**NVIDIA headless rendering:** The service sets `WLR_RENDERER=gles2` because older wlroots versions have DRM format modifier issues with NVIDIA's Vulkan renderer in headless mode. This is the safe default for the proprietary driver.

## What the Install Script Does

The `install.sh` script is a simplified fork targeting this specific system. It does straight-line `cp` operations with no runtime detection or templating:

1. **Checks `input` group membership** — offers to add the user if missing. Sets a flag to skip auto-start if a re-login is needed.
2. **Installs dependencies** — `sway`, `swaybg`, and `xdg-desktop-portal-wlr` via pacman.
3. **Checks Sunshine is installed** — verifies `/usr/bin/sunshine` exists.
4. **Copies config files** — Sway config, resolution scripts, audio restore script, `sunshine.conf`, and `apps.json` (Desktop session only).
5. **Copies systemd services** — both `sway-sunshine.service` and `sunshine-headless.service`.
6. **Installs PipeWire null sink** — copies config and restarts PipeWire.
7. **Removes stale udev rule** — if a previous input isolation rule exists, it's removed (it breaks headless Sway input).
8. **Enables services and masks system Sunshine** — prevents port conflicts.
9. **Offers to start** — or warns about re-login if the `input` group was just added.

## Installation

```bash
cd /home/salim/Code/Forks/sunshine-headless-sway
./install.sh
```

If the script adds you to the `input` group, you must **log out and back in** before proceeding. Then:

```bash
systemctl --user start sway-sunshine.service
```

## Verification

After starting services, verify everything is working:

```bash
# Both services should be active
systemctl --user status sway-sunshine sunshine-headless

# Headless Wayland display should exist
ls /run/user/$(id -u)/wayland-1

# Sway IPC socket should respond
SWAYSOCK=/run/user/$(id -u)/sway-sunshine.sock swaymsg -t get_outputs
# Expected: HEADLESS-1 at 1920x1080 (default resolution)

# PipeWire null sink should be loaded
wpctl status | grep sunshine
# Expected: sink-sunshine-stereo

# Sunshine web UI should be accessible
# Open https://<hostname>:47990 in a browser
```

## Pairing with Moonlight

1. Install [Moonlight](https://moonlight-stream.org/) on your client device
2. Open Moonlight — your host should appear on the local network
3. Select the host — Moonlight will show a 4-digit PIN
4. Enter the PIN in the Sunshine web UI at `https://<hostname>:47990`
5. Once paired, select "Desktop" to start streaming

The virtual display will automatically resize to match your client's resolution and refresh rate.

## Troubleshooting

### Services fail to start

```bash
# Check sway logs
journalctl --user -u sway-sunshine -n 50

# Check sunshine logs
journalctl --user -u sunshine-headless -n 50
```

### Black screen / no video

- Verify `WLR_RENDERER=gles2` is set in `sway-sunshine.service`
- Check that Sunshine is using the correct Wayland display: `grep WAYLAND ~/.config/systemd/user/sunshine-headless.service`
- Check `~/.config/sunshine/sunshine.log` for capture errors

### No input in streaming session

- If a udev rule exists at `/etc/udev/rules.d/85-sunshine-input-isolation.rules`, **remove it** — it strips `ID_INPUT` tags and hides Sunshine's devices from Sway's libinput backend
- Verify you're in the `input` group: `id -nG | grep input`
- Check Sway sees the virtual inputs while Moonlight is connected: `SWAYSOCK=/run/user/$(id -u)/sway-sunshine.sock swaymsg -t get_inputs` — look for devices with vendor `48879`

### Audio bleeds to host speakers

- Verify `audio_sink = sink-sunshine-stereo` in `~/.config/sunshine/sunshine.conf`
- Verify `PULSE_SINK=sink-sunshine-stereo` in the sway-sunshine service
- Check default sink after connecting: `wpctl status | grep '\*'`

### Port conflicts

If Sunshine fails to bind ports, the system `sunshine.service` may be running:

```bash
systemctl --user status sunshine.service
# If active, stop and mask it:
systemctl --user stop sunshine.service
systemctl --user mask sunshine.service
```

## Potential Issues

- **Sunshine version**: The installed version (v2025.924) is older than the upstream recommendation (v2026.226+). If `SUNSHINE_CLIENT_*` environment variables aren't populated in prep commands, upgrading Sunshine may be necessary.
- **xdg-desktop-portal conflict**: Both `xdg-desktop-portal-wlr` and `xdg-desktop-portal-kde` will be installed. The headless session sets `XDG_CURRENT_DESKTOP=sway` to route portal requests to the wlr portal in that session.
- **Resource usage**: The headless Sway session uses approximately 420MB RAM and negligible CPU when idle.

## Key Files

```
~/.config/
├── pipewire/pipewire.conf.d/
│   └── sunshine-null-sink.conf          # Persistent PipeWire null sink
├── sway-sunshine/
│   ├── config                           # Headless Sway compositor config
│   ├── set-resolution.sh               # Dynamic resolution on client connect
│   ├── reset-resolution.sh             # Reset to 1080p on disconnect
│   └── restore-default-sink.sh         # Prevents audio sink hijacking
├── sunshine/
│   ├── sunshine.conf                    # audio_sink + capture settings
│   └── apps.json                        # Desktop session entry for Moonlight
└── systemd/user/
    ├── sway-sunshine.service            # Headless Sway (WLR_RENDERER=gles2, sg input)
    └── sunshine-headless.service        # Sunshine pointed at wayland-1
```
