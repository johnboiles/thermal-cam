# Thermal Master P1 USB protocol notes

These notes describe the subset needed for a macOS live viewer. They were verified against a physical P1 on September 1, 2026.

## Identity

| Field | Value |
|---|---:|
| USB vendor ID | `0x3474` |
| USB product ID | `0x45C2` |
| Model | P1 |
| Sensor | 160 × 120 |
| Observed firmware | `00.00.00.04` |
| Frame rate | approximately 25 fps |

The tested unit returned its serial successfully through register `0x07`; the
device-specific value is intentionally omitted from this public document.

## Interface layout

- Interface 0 carries vendor control commands.
- Interface 1, alternate setting 0 is idle.
- Interface 1, alternate setting 1 enables streaming.
- Bulk IN endpoint `0x81` carries frames.

This is not usable as a normal macOS UVC/AVFoundation camera. The device appears in the USB registry, but not in the AVFoundation camera list.

## Vendor transfers

| Direction/type | Request | Purpose |
|---|---:|---|
| `0x41` | `0x20` | Send an 18-byte command |
| `0xC1` | `0x21` | Read command response |
| `0xC1` | `0x22` | Read one-byte status/acknowledgement |
| `0x40` | `0xEE` | Enable the stream after selecting alt setting 1 |

The important command packets are in `P1Camera.swift`. Register reads use command type `0x0101`; the stream command uses `0x012F`; shutter calibration uses `0x0136`.

## Start sequence

1. Set configuration 1 and claim interfaces 0 and 1.
2. Send the stream-start command; read status, one response byte, and status again.
3. Wait one second.
4. Select interface 1, alternate setting 1.
5. Send device request `0xEE`, index 1.
6. Wait two seconds and prime endpoint `0x81` with a short read.
7. Send the stream-start command again with the same acknowledgement sequence.
8. Read bulk transfers continuously.

Observed acknowledgement values are normally `0x02` after a write and `0x03` after a response read. A start response of ASCII `5` (`0x35`) indicates a stream restart.

## Frame format

Each P1 wire frame is 77,464 bytes:

| Region | Bytes | Description |
|---|---:|---|
| Start marker | 12 | sync `0x8C`/`0x8D`, counters |
| Display plane | 38,400 | 120 × 160 little-endian words; low byte is hardware-AGC intensity |
| Metadata | 640 | 2 × 160 little-endian words |
| Radiometric plane | 38,400 | 120 × 160 little-endian temperature words |
| End marker | 12 | sync `0x8E`/`0x8F`, matching frame counter |

The radiometric conversion is:

```text
degrees Celsius = raw / 64 - 273.15
```

This conversion was live-validated in the default high-sensitivity gain mode.
The extended-range gain command is implemented in the core for further research,
but is intentionally not exposed in the app: the tested P1 needs an additional
range-specific radiometric correction before its low-gain temperatures are trustworthy.

Start and end marker counters must match. The implementation also uses the dedicated 12-byte end-marker transfer to regain synchronization if capture begins in the middle of a frame.

## Android application validation

The manufacturer's download center supplied:

- APK: `Thermal_Master_2.3.11_[googleplay_abroad]_2606241105.apk`
- Package: `com.thermalmaster.p2telephoto`
- SHA-256: `8c54fe9c31d541fba17b2c62c76df0ce158b4aa540a9f5d34d683ba556c530ed`

JADX output confirmed explicit P1 recognition for decimal product ID `17858` (`0x45C2`), a UVC-bulk code path for P1/P3, 160×120-specific super-resolution selection, and the same `raw / 64 − 273.15` temperature conversion. Most transport details reside in bundled ARM native libraries rather than Java/Kotlin.

## Community cross-checks

Protocol behavior was cross-checked against these independent projects:

- `jvdillon/p3-ir-camera` (Apache-2.0), including `P3_PROTOCOL.md`
- `skywalker1905/thermal-camera-viewer` (Apache-2.0)
- `xaionaro-go/thermalmaster` (CC0-1.0)

No code from the official Android application is shipped with this project.
