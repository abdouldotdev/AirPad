# AirPad

Turn your iPhone or iPad into a trackpad and keyboard for your Mac, over your own
Wi-Fi. No account, no cloud, no third-party service.

## How it works

- **AirPadServer** (macOS 13+) listens on TCP port 8080 and injects mouse and
  keyboard events with `CGEvent`. It requires Accessibility permission.
- **AirPadClient** (iOS 16+) connects over TCP and sends one text command per line.

Pairing is required: the Mac generates an 8-character code, shows it in a QR code,
and rejects any connection that does not present it.

## Protocol

Line-based text over TCP. The client must authenticate first.

| Command | Meaning |
|---|---|
| `AUTH:<code>` | Pairing code — required before anything else |
| `INIT:<device>` | Device name shown on the Mac |
| `PING` / `PONG` | Heartbeat |
| `M:<dx>:<dy>` | Move pointer |
| `S:<dx>:<dy>` | Scroll |
| `C:1` / `R:1` | Left / right click |
| `K:<keycode>:<0\|1>:<flags>` | Key up/down with `CGEventFlags` |

## Build

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # then fill in the keys
xcodegen generate
xcodebuild -scheme AirPadClient -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
xcodebuild -scheme AirPadServer -destination 'platform=macOS' build
```

The Mac app is distributed as a signed and notarized DMG through
[GitHub Releases](https://github.com/abdouldotdev/MacTrack/releases/latest).
