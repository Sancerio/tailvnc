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

Mac Login mode encrypts the macOS username and password with a one-time AES key
and encrypts that key with the server's RSA key. The server key is not
independently verified, and the later framebuffer session remains unencrypted,
so the private tunnel is still the primary security boundary.

Legacy VNC authentication has an effective password length of eight bytes and
cannot authenticate a macOS user at the lock screen. Use a unique VNC password
when compatibility mode is required.

Remembered Mac account or VNC credentials are stored in the local iOS Keychain
with a device-only accessibility class. Hosts, ports, authentication mode, and
the last Mac username are stored in app preferences and are not considered
secrets.
