# Playing on an Android TV: streaming from the Mac

The game runs on the Mac; the TV shows it. Everything stays on the home network: no account, no
internet, no cloud relay. The pair of tools is [Sunshine](https://github.com/LizardByte/Sunshine)
(host, on the Mac) and [Moonlight](https://github.com/moonlight-stream/moonlight-android)
(client, on the TV), both open source.

Tested 2026-09-05 with Sunshine 2026.516 on macOS 26.5 (Apple Silicon) and Moonlight 12.1 on a
Philips TPM191E (Android 12, 32-bit ARM), both on 5 GHz Wi-Fi.

## What you need

- The exported game: `make export`, then unzip `build/Vakuraamat.zip` so that
  `build/app/Vakuraamat.app` exists (or point the app entry below at any other copy).
- `adb` on the Mac (`brew install android-platform-tools`) and ADB debugging over the network
  enabled on the TV (Settings > Device Preferences > Developer options > Network debugging).
  Sideloading is only needed because the Play Store is not always available on a TV; if it is,
  install "Moonlight Game Streaming" from there instead and skip the adb steps.
- The TV's IP address, called `TV_IP` below.

## One-time setup

### 1. Moonlight on the TV

```sh
curl -sL -o moonlight.apk \
  https://github.com/moonlight-stream/moonlight-android/releases/latest/download/app-nonRoot-release.apk
adb connect TV_IP:5555
adb install --user 0 moonlight.apk
```

`--user 0` is needed on some TVs (the Philips among them) for the install to land on the primary
user. The nonRoot APK is universal and covers 32-bit TV chipsets.

### 2. Sunshine on the Mac

Homebrew has no formula, so use the DMG:

```sh
curl -sL -o Sunshine.dmg \
  https://github.com/LizardByte/Sunshine/releases/latest/download/Sunshine-macOS-arm64.dmg
yes | hdiutil attach -nobrowse -readonly Sunshine.dmg    # "yes" accepts the GPL prompt
cp -R /Volumes/Sunshine/Sunshine.app /Applications/
hdiutil detach /Volumes/Sunshine
```

Write the configuration before the first start. `sunshine.conf` names the host as the TV will see
it and disables UPnP (nothing should be reachable from outside the LAN); `apps.json` lists what
the TV can launch. Replace `USER` with your macOS user name, or `/Users/USER` with wherever the
repository lives.

```sh
mkdir -p ~/.config/sunshine
cat > ~/.config/sunshine/sunshine.conf <<'EOF'
sunshine_name = Vakuraamat Mac
file_apps = /Users/USER/.config/sunshine/apps.json
origin_web_ui_allowed = lan
upnp = disabled
address_family = ipv4
EOF
cat > ~/.config/sunshine/apps.json <<'EOF'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    {
      "name": "Vakuraamat",
      "cmd": "/Users/USER/workspace/vakuraamat/build/app/Vakuraamat.app/Contents/MacOS/Vakuraamat -- --fullscreen",
      "auto-detach": "false",
      "wait-all": "true",
      "exit-timeout": "5"
    }
  ]
}
EOF
```

`-- --fullscreen` is the game's own flag (see `scripts/autoload/window_mode.gd`); Sunshine captures
the whole display, so the game must cover it.

Set the web UI credentials (pick your own), then start Sunshine as a normal app so macOS can show
its permission prompts:

```sh
/Applications/Sunshine.app/Contents/MacOS/Sunshine --creds WEB_USER WEB_PASSWORD
open -a Sunshine
```

Allow all three prompts: **Screen Recording** (without it Sunshine logs
`No screen capture permission!` and every encoder "fails"), **System Audio**, and **Accessibility**
(keyboard and mouse events from the TV are injected through it). If a prompt was dismissed, grant
the permission under System Settings > Privacy & Security and restart Sunshine:

```sh
pkill -x Sunshine; open -a Sunshine
tail ~/.config/sunshine/sunshine.log     # expect "Found H.264 encoder: h264_videotoolbox"
```

### 3. Pair the TV

Open Moonlight on the TV; the Mac appears within a few seconds by mDNS. Select it: Moonlight
shows a four-digit PIN. Enter the PIN either in the web UI (https://localhost:47990 > PIN) or from
the terminal:

```sh
curl -sk -u WEB_USER:WEB_PASSWORD -X POST https://localhost:47990/api/pin \
  -H 'Content-Type: application/json' -d '{"pin":"1234","name":"Living room TV"}'
```

Pairing is stored on both sides (`~/.config/sunshine/sunshine_state.json` on the Mac) and does not
need repeating. If the TV is off-screen, drive Moonlight from the Mac:

```sh
adb shell am start -n com.limelight/.PcView -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER
adb shell input keyevent KEYCODE_DPAD_CENTER          # select the Mac
adb exec-out screencap -p > tv.png                     # read the PIN from the screenshot
```

## Playing

1. On the Mac: `open -a Sunshine` (it stays in the menu bar; you can also add it to Login Items).
2. On the TV: open Moonlight, pick the Mac, pick **Vakuraamat**. Sunshine starts the game
   fullscreen on the Mac and the TV shows it. Back on the remote (Ctrl+Alt+Shift+Q on a
   keyboard) ends the stream, and Sunshine quits the game with it. **Desktop** streams whatever is on screen without launching anything.
3. Bring the game's fullscreen Space to the front on the Mac if another window is showing:
   Sunshine streams the display, not a window.

Useful commands while it runs:

```sh
tail -f ~/.config/sunshine/sunshine.log                       # sessions, encoder, errors
curl -sk -u WEB_USER:WEB_PASSWORD -X POST https://localhost:47990/api/apps/close   # end the session and quit the game
adb exec-out screencap -p > tv.png                            # what the TV is showing
```

## Input

Sunshine on macOS forwards keyboard and mouse only; **gamepads do not work** on a macOS host (no
virtual controller driver, see LizardByte discussion #130). The game binds both WASD and the arrow
keys, and Moonlight sends a TV remote's D-pad as arrow keys, so basic walking works from the remote
once Accessibility is granted. For full control use a keyboard and mouse at the Mac, or a
Bluetooth keyboard paired to the TV. A game-side input listener (WebSocket, driven from a phone or
a small TV app) is the planned way around the gamepad gap.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Moonlight: "Failed to start ... (error 503)", host says video capture failed | Screen Recording not granted, or Sunshine was restarting. Grant it, restart Sunshine, retry. |
| "Slow connection to PC, reduce your bitrate" with no packet loss | Wi-Fi jitter (measured up to ~100 ms on a Wi-Fi to Wi-Fi path). Put the Mac or the TV on Ethernet, or lower the bitrate in Moonlight > Settings. |
| TV shows the desktop instead of the game | The game's fullscreen Space is not in front on the Mac. Switch to it. |
| The Mac does not appear in Moonlight's list | Sunshine not running, or mDNS blocked between Wi-Fi clients. Use the **+** button in Moonlight and enter the Mac's IP. |
| `hdiutil attach` says "attach canceled" | The DMG has a licence prompt; pipe `yes` into it as above. |
| Game exits at once when started from the TV | Path in `apps.json` is wrong or the export is stale; run the `cmd` line by hand in a terminal. |
