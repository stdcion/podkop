# Routerich AX3000

Scripts for initial setup of Routerich AX3000 with podkop.

## Files

- `firstboot.sh` - initial router configuration (hostname, WiFi, NTP, root password, button setup, downloads toggle script)
- `toggle_podkop` - toggle podkop on/off via hardware button, with LED indication

## Quick start

Run on the router:

```sh
sh <(wget -O - https://raw.githubusercontent.com/stdcion/podkop/main/devices/routerich-ax3000/firstboot.sh)
```

The script will download everything it needs automatically.

## What firstboot.sh does

Interactively configures:

- Hostname (default: `Routerich`)
- Router IP (default: `192.168.1.1`)
- Root password (default: `toor`)
- WiFi SSID and key (default: `Routerich` / `12345678`)
- NTP servers (Google, Cloudflare)
- Timezone (MSK)
- HTTPS redirect for LuCI
- Hardware button (BTN_0) to toggle podkop
- Downloads and installs `toggle_podkop` to `/usr/bin/`

## Hardware button

After setup, short press (1-5 sec) on the router button will toggle podkop:

- **LED on** - podkop is running
- **LED blinking** - toggling in progress
- **LED off** - podkop is stopped

Manual control:

```sh
toggle_podkop on      # enable and start podkop
toggle_podkop off     # stop and disable podkop
toggle_podkop toggle  # switch state
```
