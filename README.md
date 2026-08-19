# TailVNC

TailVNC is a small, open-source VNC client for iPhone and iPad. It is designed
for direct connections to computers that are already reachable through a
private network such as Tailscale.

There is no TailVNC account, cloud relay, analytics SDK, or companion agent.
The app speaks the Remote Framebuffer (RFB) protocol directly to the server.

## Status

TailVNC is an early MVP. It currently targets the smallest useful feature set:

- RFB 3.8 negotiation plus Apple's `RFB 003.889` account-authentication path
- Apple RSA/AES Mac account authentication (security type 33)
- standard VNC challenge-response authentication as a legacy fallback
- Tight/JPEG compressed framebuffer updates with a raw 32-bit fallback
- live Responsive, Balanced, and Sharp stream-quality modes
- touch pointer input, dragging, scrolling, pinch-to-zoom (up to 4×), and panning
- immediate local input-sent feedback while the remote frame is in flight
- software and hardware keyboard input for common keys
- optional credential storage in the iOS Keychain
- direct host, MagicDNS name, or IP address connections

TailVNC defaults to Responsive mode. The three modes keep the Mac's desktop
geometry intact and adjust the standard RFB Tight JPEG quality/compression hints
instead of changing the Mac's real display resolution and rearranging windows.
Servers that do not support Tight encoding automatically fall back to raw pixels.

## Threat model

Classic VNC does not encrypt the framebuffer stream. TailVNC should only be
used inside a trusted encrypted tunnel such as Tailscale, WireGuard, or an SSH
tunnel. Never expose TCP port 5900 directly to the public internet.

Mac Login encrypts the username and password during authentication, but it
does not encrypt the later framebuffer session or independently verify the
Mac's public key. Treat the private network tunnel as the primary security
boundary. Standard VNC authentication uses only the first eight password
bytes and cannot log in to a locked macOS account. TailVNC stores remembered
credentials with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; it does not sync the
credentials through iCloud.

See [SECURITY.md](SECURITY.md) for the security policy and current limitations.

## macOS setup

1. Install and connect Tailscale on the Mac and iPhone.
2. On the Mac, open **System Settings → General → Sharing**.
3. Turn on **Screen Sharing**.
4. Open its details and keep **Allow access for** limited to the intended users.
5. Use TailVNC's recommended **Mac Login** mode with an allowed macOS account.
   Only enable **VNC viewers may control screen with password** if you need the
   legacy compatibility mode; it cannot unlock the Mac login screen.
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
negotiation, Apple RSA/AES account authentication, legacy VNC authentication,
Tight framebuffer delivery, quality negotiation, and the next incremental update
request end to end.
GitHub Actions also runs the unit, protocol integration, and UI tests on every
push and pull request.

To run on a physical iPhone, open `TailVNC.xcodeproj`, select your Apple
development team for the TailVNC target, and run it on the connected device.

## Architecture

- `RFBClient` owns the TCP connection and protocol state machine.
- `VNCAuthentication` implements the standard DES challenge response in pure
  Swift.
- `AppleRSAAuthentication` implements macOS security type 33 using Security
  and CommonCrypto system frameworks.
- `TightDecoder` handles fill, JPEG, palette, gradient, and persistent-zlib Tight
  rectangles using Apple image frameworks and the system zlib library.
- `RFBFrameBuffer` applies raw and decoded rectangles and emits RGBA `CGImage`
  frames.
- SwiftUI views provide connection setup and remote input controls.
- `KeychainStore` is the only persistence layer for credentials.

## Roadmap

- ZRLE encoding
- cursor pseudo-encoding
- clipboard sync controls
- richer hardware keyboard mapping
- multi-display selection
- measured adaptive quality based on observed throughput

Contributions are welcome. Please keep new dependencies and network services
out of the default path unless they materially improve security or
interoperability.
