# Security policy

## Supported versions

TailVNC is pre-release software. Security fixes are applied to the latest
version on the default branch.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose a
credential or remote desktop session. Use GitHub's private vulnerability
reporting feature for this repository.

## Security boundaries

TailVNC intentionally does not provide a relay, identity service, or encrypted
VNC transport. Classic VNC framebuffer traffic is unencrypted. Users must
provide a trusted encrypted path such as Tailscale, WireGuard, or SSH and must
not expose the server's VNC port to the public internet.

VNC authentication is a legacy protocol with an effective password length of
eight bytes. A unique VNC password is still required, but the private network
is the primary access-control boundary.

Remembered passwords are stored in the local iOS Keychain with a
device-only accessibility class. Hosts and ports are stored in app preferences
and are not considered secrets.
