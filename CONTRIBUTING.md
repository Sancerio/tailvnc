# Contributing

Thank you for helping improve TailVNC.

1. Open an issue describing the interoperability problem or feature.
2. Keep protocol changes covered by unit tests.
3. Do not add telemetry, accounts, relays, or credential logging.
4. Run the unit and UI tests before opening a pull request.
5. Explain any new dependency and why a small in-tree implementation is not
   appropriate.

Bug reports are most useful when they include the server implementation, RFB
version, advertised security types, and encoding list. Never include a VNC
password, private key, or full packet capture from a sensitive session.
