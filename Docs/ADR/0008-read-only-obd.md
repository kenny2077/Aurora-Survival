# ADR 0008: OBD is read-only by construction

Status: Accepted

The app exposes an explicit allowlist of observation commands. Clearing codes,
ECU writes, actuator control, safety-system bypass, and arbitrary commands are
rejected before reaching a transport.

Consequence: physical BLE adapters and vehicles still require isolation and
no-write capture tests.
