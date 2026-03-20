# Uninstall / Revert

Steps to undo everything `install.sh` does.

## 1. Stop and disable services

```bash
systemctl --user stop sway-sunshine sunshine-headless
systemctl --user disable sway-sunshine sunshine-headless
systemctl --user unmask sunshine.service
systemctl --user unmask app-dev.lizardbyte.app.Sunshine.service
```

## 2. Remove installed files

```bash
# Sway headless config and scripts
rm -rf ~/.config/sway-sunshine

# Systemd service units
rm -f ~/.config/systemd/user/sway-sunshine.service
rm -f ~/.config/systemd/user/sunshine-headless.service

# PipeWire null sink
rm -f ~/.config/pipewire/pipewire.conf.d/sunshine-null-sink.conf
```

## 3. Restore Sunshine config

If you backed up before installing:

```bash
cp ~/.config/sunshine/sunshine.conf.bak ~/.config/sunshine/sunshine.conf
cp ~/.config/sunshine/apps.json.bak ~/.config/sunshine/apps.json
```

## 4. Reload daemons

```bash
systemctl --user daemon-reload
systemctl --user restart pipewire
```

## 5. Optional: remove packages

These were installed by the script and can be removed if nothing else needs them:

```bash
sudo pacman -Rs sway swaybg xdg-desktop-portal-wlr
```

## 6. Optional: remove input group membership

```bash
sudo gpasswd -d "$USER" input
```
