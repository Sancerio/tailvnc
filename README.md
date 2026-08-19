# TailVNC

TailVNC is a small, open-source VNC client for iPhone and iPad. It is designed
for direct connections to computers that are already reachable through a
private network such as Tailscale.

There is no TailVNC account, cloud relay, analytics SDK, or companion agent.
The app speaks the Remote Framebuffer (RFB) protocol directly to the server.

## Status

TailVNC is an early MVP. It currently targets the smallest useful feature set:

- RFB 3.8 negotiation, including Apple's `RFB 003.889` greeting
- standard VNC challenge-response authentication
- raw framebuffer updates in 32-bit true color
- touch pointer input, dragging, scrolling, pinch-to-zoom (up to 4×), and panning
- software and hardware keyboard input for common keys
- optional password storage in the iOS Keychain
- direct host, MagicDNS name, or IP address connections

The first release intentionally supports only raw framebuffer encoding. It is
correct and easy to audit, but not yet bandwidth-efficient for high-motion use.

## Threat model

Classic VNC does not encrypt the framebuffer stream. TailVNC should only be
used inside a trusted encrypted tunnel such as Tailscale, WireGuard, or an SSH
tunnel. Never expose TCP port 5900 directly to the public internet.

Standard VNC authentication uses only the first eight password bytes. Use a
unique VNC password and treat the private network tunnel as the primary
security boundary. TailVNC stores a remembered password with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; it does not sync the
password through iCloud.

See [SECURITY.md](SECURITY.md) for the security policy and current limitations.

## macOS setup

1. Install and connect Tailscale on the Mac and iPhone.
2. On the Mac, open **System Settings → General → Sharing**.
3. Turn on **Screen Sharing**.
4. Open its details and keep **Allow access for** limited to the intended users.
5. Enable **VNC viewers may control screen with password** and create a unique
   password.
6. Do not forward port 5900 on the router.

In TailVNC, connect to the Mac's Tailscale IP (usually `100.x.x.x`) or its
MagicDNS name on port `5900`.

## Build

Requirements:

- Xcode 16 or newer
- XcodeGen
- iOS 17 or newer

```sh
brew install xcodegen
xcodegen generate
xcodebuild \
  -project TailVNC.xcodeproj \
  -scheme TailVNC \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The test suite includes a local mock RFB server that verifies protocol
negotiation, VNC authentication, raw framebuffer delivery, and the next
incremental update request end to end. GitHub Actions also runs the unit,
protocol integration, and UI tests on every push and pull request.

To run on a physical iPhone, open `TailVNC.xcodeproj`, select your Apple
development team for the TailVNC target, and run it on the connected device.

## Architecture

- `RFBClient` owns the TCP connection and protocol state machine.
- `VNCAuthentication` implements the standard DES challenge response in pure
  Swift, keeping the project dependency-free.
- `RFBFrameBuffer` applies raw rectangles and emits RGBA `CGImage` frames.
- SwiftUI views provide connection setup and remote input controls.
- `KeychainStore` is the only persistence layer for credentials.

## Roadmap

- Tight and ZRLE encodings
- cursor pseudo-encoding
- clipboard sync controls
- richer hardware keyboard mapping
- multi-display selection
- per-connection quality settings

Contributions are welcome. Please keep new dependencies and network services
out of the default path unless they materially improve security or
interoperability.
