# Sunshine Error 503 — KDE Plasma Wayland Investigation & Fix Guide

## Status: ROOT CAUSE IDENTIFIED — FIX AVAILABLE

**Date**: 2026-04-23
**Sunshine version**: 2025.924.154138 (commit 86188d47)
**Host**: CachyOS KDE Plasma Wayland
**GPU**: AMD Radeon 8060S (card1/renderD128) — NVIDIA RTX 5090 restricted for AI

---

## ROOT CAUSE

The LutrisToSunshine nested sway approach **does not work on KDE Plasma Wayland**. It was tested only on Aurora/Ublue (GNOME/Mutter).

The fundamental issue is a **compositor protocol mismatch**:

| Compositor | Protocol for screen capture | Sunshine capture method |
|------------|----------------------------|------------------------|
| wlroots (Sway, Hyprland) | `zwlr_screencopy_unstable_v1` | `capture = wlr` |
| KWin (KDE Plasma) | `zkde_screencast_unstable_v1` via XDG portal | `capture = portal` |

**KWin does NOT implement `zwlr_screencopy_unstable_v1`** (KDE Bug #518354, still open). All attempts to use `capture = wayland`, `capture = wlr`, or `capture = pipewire` fail because KWin doesn't speak the wlroots screencopy protocol.

The nested sway compositor (running on `wayland-1`) DOES expose `zwlr_screencopy_manager_v1`, but Sunshine's EGL layer fails with `EGL_BAD_PARAMETER` on `eglQueryDeviceStringEXT(EGL_DRM_DEVICE_FILE_EXT)` — nested Wayland inside Plasma has no direct DRM device, so EGL surfaces can't be created for encoding.

---

## CONFIRMED WORKING FIX: `capture = portal`

**Source**: Reddit post r/MoonlightStreaming (2026-04-18) — "Sunshine + Moonlight fully working on KDE Plasma Wayland"

### What is `capture = portal`?

Added to Sunshine in **PR #4417** (merged Feb 2026). Uses the **XDG Desktop Portal** (`org.freedesktop.portal.ScreenCast`) combined with **PipeWire** for screen capture. Works on KDE Plasma, GNOME, and any desktop with an XDG portal backend.

### Data Flow
```
Sunshine → XDG Desktop Portal (D-Bus) → xdg-desktop-portal-kde → KWin Wayland → PipeWire stream → Sunshine encoder → Moonlight
```

### Configuration
```ini
# ~/.config/sunshine/sunshine.conf
capture = portal
```

That's it. No `output_name` needed. No nested compositor needed.

### Version Compatibility
- **Portal capture was merged in Feb 2026** — your Sunshine version (2025.924.154138) was released Sept 2025 and **may NOT have portal support**.
- Check if `capture = portal` is recognized: look for `portalgrab` or `xdg-desktop-portal` in `strings /usr/bin/sunshine-2025.924.154138`.
- If NOT present: **upgrade Sunshine** to a version after Feb 2026 (check AUR for `sunshine-git` or newer release).

### Headless Portal Permission Approval
Normally, the first portal capture request shows a permission dialog. For headless/server use:

```bash
# If Sunshine is Flatpak:
flatpak permission-set kde-authorized remote-desktop dev.lizardbyte.app.Sunshine yes

# If Sunshine is native (systemd service):
# The portal D-Bus session must be available to the sunshine process.
# Your current systemd override clears WAYLAND_DISPLAY and SWAYSOCK.
# For portal, you need the portal's environment. Add to systemd override:
EnvironmentFile=/home/moe/.config/sunshine/portal-env
```

Where `portal-env` contains the D-Bus session address and WAYLAND_DISPLAY of the Plasma session.

### Known Issues with Portal (from Sunshine GitHub)
| Issue | Ref | Status | Workaround |
|-------|-----|--------|------------|
| XWayland game stuttering on KWin | #4884 | Open | `PROTON_ENABLE_WAYLAND=1` in Steam launch options |
| Multi-monitor squished into one stream | #4914 | Fixed PR #4931 | Upgrade Sunshine |
| Fractional scaling partial capture | #4672 | Fixed PR #4700 | Upgrade Sunshine |
| PipeWire 1.6.0 format negotiation | #4824 | Fixed PR #4875 | Upgrade Sunshine |

---

## ALTERNATIVE: KMS Capture on AMD (with KWIN env fixes)

If portal is not available or you want compositor-bypass capture:

### Configuration
```ini
# ~/.config/sunshine/sunshine.conf
capture = kms
adapter_name = /dev/dri/renderD128
output_name = 0
```

### Required Environment Variables (KDE Plasma specific)
Add to systemd override or `/etc/environment`:
```ini
# Prevent KWin direct scan-out from cropping fullscreen apps
KWIN_DRM_NO_DIRECT_SCANOUT=1

# Prevent CPU spikes from hardware cursor changes
KWIN_FORCE_SW_CURSOR=1
```

### Required Capability
```bash
sudo setcap cap_sys_admin+p /usr/bin/sunshine-2025.924.154138
```

### Known Issues with KMS on KDE
| Issue | Severity | Notes |
|-------|----------|-------|
| KWin direct scan-out crops fullscreen apps | High | Fixed by `KWIN_DRM_NO_DIRECT_SCANOUT=1` |
| Cursor shape changes spike CPU | Medium | Fixed by `KWIN_FORCE_SW_CURSOR=1` |
| Fractional scaling broken | Medium | No workaround — use 100% scaling |
| Multi-GPU RGB import errors | High | Set `CUDA_VISIBLE_DEVICES=N` in systemd |

---

## WHY NESTED SWAY FAILS ON PLASMA

### The EGL Error Chain
```
1. Sway starts nested inside Plasma (WLR_BACKENDS=wayland)
2. Sway creates Wayland compositor on wayland-1
3. EGL tries to query DRM device: eglQueryDeviceStringEXT(EGL_DRM_DEVICE_FILE_EXT)
4. Returns EGL_BAD_PARAMETER — no DRM device in nested topology
5. No EGL surfaces can be created
6. Sunshine's capture layer can't initialize
7. Encoder tests (nvenc/vaapi/software) all fail — no video source to encode
```

### Why It Works on Aurora/Ublue
Aurora uses GNOME/Mutter as host compositor. Mutter's Wayland backend allows nested compositors to access GPU surfaces. KWin's Wayland backend does NOT permit this — EGL fails.

### All Renderer Fixes Tested (All Failed)
| Attempt | What Changed | Result |
|---------|-------------|--------|
| `WLR_RENDERER=pixman` | Default software renderer | EGL fails, no GPU surfaces |
| `WLR_RENDERER=gles2` | OpenGL ES 2.0 renderer | EGL still fails |
| `EGL_DEVICE_FILE=/dev/dri/card1` | Explicit AMD GPU | No effect — wlroots still can't query DRM |
| `GBM_BACKEND=dri` | DRI buffer backend | No effect |
| `WLR_RENDERER_ALLOW_SOFTWARE=1` | Software fallback | No effect |
| `LIBVA_DRIVER_NAME=radeonsi` | VAAPI AMD targeting | Encoder tests never reached (capture failed first) |
| `RENDER_NODE=/dev/dri/renderD128` | Explicit render node | No effect |
| Gamescope instead of sway | Different nested compositor | No screencopy protocols at all |
| `capture = pipewire` | PipeWire capture | Platform init fails |
| `capture = x11` | X11 capture | Platform init fails |

---

## VIRTUAL DISPLAY ON SINGLE MONITOR (EDID Injection)

If you want a **separate virtual display** for games (isolated from your main DP-4), you can create one via EDID injection on a disconnected AMD connector.

### Why This Works
The AMD GPU (card1) has multiple connectors: DP-1 through DP-8, HDMI-A-1. Only DP-4 is connected. You can trick the kernel into thinking another monitor is plugged in on any disconnected connector.

### Steps

**1. Generate an EDID binary for 1920x1080@60Hz:**
```bash
# Install parse-edid if not available
sudo pacman -S parse-edid

# Generate EDID
parse-edid --make --vtb 1920x1080@60 --monitor-name "LutrisToSunshine" --monitor-mfr LGS --monitor-model "Virtual 1080p" | create-edid > /tmp/1920x1080.bin

# Install to firmware directory
sudo cp /tmp/1920x1080.bin /usr/lib/firmware/edid/1920x1080.bin
```

**2. Add kernel parameters (GRUB):**
```bash
# Edit /etc/default/grub, append to GRUB_CMDLINE_LINUX:
drm.edid_firmware=HDMI-A-1:edid/1920x1080.bin video=HDMI-A-1:e
```

**3. Rebuild initramfs and GRUB:**
```bash
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

**4. After reboot, verify:**
```bash
cat /sys/class/drm/card1-HDMI-A-1/status  # should show "connected"
cat /sys/class/drm/card1-HDMI-A-1/edid    # should show EDID data
```

**5. Configure KDE to use the new display:**
```bash
# Enable the virtual output
kscreen-doctor output.HDMI-A-1.enable
kscreen-doctor output.HDMI-A-1.mode.1920x1080@60
kscreen-doctor output.HDMI-A-1.position.1920,0  # position to the right of DP-4
```

**6. Use with Sunshine:**
- With `capture = portal`: portal will see both displays, you can select the virtual one
- With `capture = kms`: set `output_name` to the HDMI-A-1 monitor index

### Post-Boot EDID Override (No Reboot Needed)
```bash
# Override EDID via sysfs (requires root)
sudo bash -c 'cat /usr/lib/firmware/edid/1920x1080.bin > /sys/class/drm/card1-HDMI-A-1/edid_override'

# Force-enable connector
sudo bash -c 'echo 1 > /sys/class/drm/card1-HDMI-A-1/status'
```

---

## VKMS VIRTUAL DISPLAY (Software-Only, No Hardware Encoding)

The Arch Wiki mentions **VKMS** (Virtual Kernel Mode Setting) as a headless option. This creates a virtual DRM device independent of your physical GPU.

```bash
sudo modprobe vkms
```

**Why VKMS is NOT recommended for Sunshine:**
- No hardware encoding on the virtual device
- Separate from your physical GPU
- Limited mode setting features
- KWin may not recognize it as a valid output

EDID injection on your existing AMD GPU is superior — it uses the real GPU for hardware encoding.

---

## CURRENT FILES MODIFIED

| File | Changes | Status |
|------|---------|--------|
| `~/.config/lutristosunshine/bin/lutristosunshine-start-headless-sway.sh` | WLR_RENDERER=gles2, EGL_DEVICE_FILE, GBM_BACKEND | **Revert to original** — nested sway doesn't work on Plasma |
| `~/.config/lutristosunshine/bin/lutristosunshine-start-display-sunshine.sh` | env -i, AMD vars, DISPLAY=:0 | **Revert to original** |
| `~/.config/sunshine/sunshine.conf` | capture method changes | **Set to `capture = portal`** or **`capture = kms`** |
| `~/.config/lutristosunshine/bin/lutristosunshine-start-gamescope.sh` | Created (gamescope nested compositor) | **Remove** — not needed |
| `~/.config/lutristosunshine/bin/lutristosunshine-run-display-service.sh` | Changed to use gamescope | **Revert to sway** or **simplify for portal** |

---

## RECOMMENDED ACTION PLAN

### Path A: Portal Capture (Preferred)
1. **Check if portal capture is available**: `grep -i "portal" /usr/bin/sunshine-2025.924.154138` or `strings /usr/bin/sunshine-2025.924.154138 | grep -i portalgrab`
2. **If YES**: Set `capture = portal` in sunshine.conf, restart Sunshine
3. **If NO**: Upgrade Sunshine (AUR `sunshine-git` or wait for newer release)
4. **Approve portal permission**: `flatpak permission-set kde-authorized remote-desktop dev.lizardbyte.app.Sunshine yes` (if Flatpak) or handle via D-Bus session
5. **Simplify LutrisToSunshine scripts**: For portal capture, the nested compositor is NOT needed. Sunshine captures the Plasma desktop directly.
6. **Test**: Connect Moonlight, verify stream quality

### Path B: KMS Capture (Alternative)
1. Set `capture = kms` in sunshine.conf
2. Set `adapter_name = /dev/dri/renderD128`
3. Add `KWIN_DRM_NO_DIRECT_SCANOUT=1` and `KWIN_FORCE_SW_CURSOR=1` to systemd override
4. Verify `cap_sys_admin` on Sunshine binary
5. Test

### Path C: Virtual Display + Portal (Full Isolation)
1. EDID injection on HDMI-A-1 (see above)
2. Configure kscreen-doctor for dual display
3. Use `capture = portal` pointing to virtual display
4. Run games on virtual display via LutrisToSunshine

---

## KEY REFERENCES

| Resource | URL | Notes |
|----------|-----|-------|
| Sunshine PR #4417 (portal capture) | https://github.com/LizardByte/Sunshine/pull/4417 | Added Feb 2026, now default for Wayland |
| Sunshine Issue #4982 (KWin scan-out) | https://github.com/LizardByte/Sunshine/issues/4982 | KMS cropping fix |
| Sunshine Issue #4884 (XWayland stutter) | https://github.com/LizardByte/Sunshine/issues/4884 | PROTON_ENABLE_WAYLAND=1 fix |
| Sunshine Issue #4914 (multi-monitor) | https://github.com/LizardByte/Sunshine/issues/4914 | Fixed PR #4931 |
| Sunshine Issue #4672 (fractional scaling) | https://github.com/LizardByte/Sunshine/issues/4672 | Fixed PR #4700 |
| KDE Bug #518354 (no zwlr_screencopy) | https://bugs.kde.org/show_bug.cgi?id=518354 | KWin doesn't support wlroots screencopy |
| KDE Bug #485850 (virtual screen 1920x1080) | https://bugs.kde.org/show_bug.cgi?id=485850 | xdg-desktop-portal-kde hardcoded resolution |
| Arch Wiki: Headless | https://wiki.archlinux.org/title/Headless | EDID injection, VKMS, virtual displays |
| Arch Wiki: XDG Desktop Portal | https://wiki.archlinux.org/title/XDG_Desktop_Portal | Portal architecture, screen capture |
| Kernel docs: drm.edid_firmware | https://docs.kernel.org/admin-guide/kernel-parameters.html | EDID injection syntax |
| Reddit: Sunshine on KDE Plasma | https://www.reddit.com/r/MoonlightStreaming/comments/1sp8l9q/ | Working setup, Apr 2026 |
| LutrisToSunshine README | https://github.com/Arbitrate3280/LutrisToSunshine | Only tested on Aurora/Ublue |
| Wayland Explorer: kde-zkde-screencast | https://wayland.app/protocols/kde-zkde-screencast-unstable-v1 | KWin's screencast protocol |

---

## ARCH WIKI HEADLESS PAGE SUMMARY

From https://wiki.archlinux.org/title/Headless:

### Virtual Display Approaches

| Approach | Module | Creates New DRM Device | Hardware Encoding | Use Case |
|----------|--------|----------------------|-------------------|----------|
| **EDID Injection** | `drm.edid_firmware=` + `video=CON:e` | No — uses existing GPU | **Yes** (full GPU) | **Best for Sunshine** |
| **VKMS** | `vkms` kernel module | Yes (virtual DRM) | No (software) | CI/testing |
| **EVDI** | `evdi` kernel module | Yes (virtual DRM) | No (user-space) | Barin, virtual monitors |

### EDID Injection Details
- Kernel parameter: `drm.edid_firmware=HDMI-A-1:edid/1920x1080.bin`
- Connector enable: `video=HDMI-A-1:e`
- EDID file location: `/lib/firmware/edid/`
- Must be in initramfs for early boot
- Kernel 4.13+: `drm.edid_firmware=` (was `drm_kms_helper.edid_firmware=` before)
- Post-boot override: `cat edid.bin > /sys/class/drm/cardX-CONNECTION/edid_override`

### VKMS Details
- Load: `modprobe vkms`
- Configfs (kernel 6.10+): `/sys/kernel/config/vkms/`
- Creates separate DRM device (not your physical GPU)
- No hardware encoding — software rendering only
- Not recommended for game streaming

### kwin_wayland --virtual
- KWin supports `--virtual` flag for testing without physical monitor
- `startplasma-wayland` does NOT forward this flag
- Practical solution: EDID injection to trick GPU into creating output

---

## HARDWARE REFERENCE

| Device | PCI | DRI Node | Permissions | Accessible? |
|--------|-----|----------|-------------|-------------|
| NVIDIA RTX 5090 | `03:00.0` | `card0`, `renderD129` | `c---------` | NO (AI workloads) |
| AMD Radeon 8060S | `c2:00.0` | `card1`, `renderD128` | `crw-rw-rw-` | YES |

AMD GPU connectors: DP-1 through DP-8, HDMI-A-1, Writeback-1
Only **DP-4** is connected (main display).

---

## WHAT THE NEXT AGENT SHOULD DO

1. **First**: Check if `capture = portal` is available in current Sunshine binary
2. **If available**: Switch to `capture = portal`, remove nested compositor scripts, test
3. **If not available**: Upgrade Sunshine, then switch to portal
4. **Fallback**: Use `capture = kms` with KWIN env var fixes
5. **For virtual display isolation**: EDID injection on HDMI-A-1, then portal or KMS capture
6. **Revert**: All nested sway/gles2/EGL changes — they don't work on Plasma
7. **Document**: Whatever works, update LutrisToSunshine repo README with KDE Plasma notes

---

## FILES NOT MODIFIED
- Nothing in `/home/moe/LutrisToSunshine/` repo (per user constraint)
