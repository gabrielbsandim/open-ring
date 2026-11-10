# Colmi Ring BLE Protocol

Status: compiled on 2026-11-10 from open implementations. **Nothing here is
verified on our ring yet.** Phase 1 marks each row verified or dropped, backed by
a captured trace in `packages/ring_protocol/test/fixtures`.

The previous version of this file listed service `0000fee7` with characteristics
`fea1`/`fea2`, an `0xAB`/`0xAA` header and commands `0x07`, `0x09`, `0x11`, `0x14`.
None of those appear in any source below, so they were removed.

## Sources

- Gadgetbridge, `devices/colmi/ColmiR0xConstants.java` (Freeyourgadget/Gadgetbridge, master)
- `tahnok/colmi_r02_client` (Python client, R02/R06/R10 fully supported)
- `colmi.puxtril.com` (commands, big data and settings pages, tested on R03)

## Device

- Target: COLMI R09 ("COLMI Ring 2"), firmware reported by QRing as `3.00.03`.
  QRing app version is a separate number; do not conflate them.
- Advertised names seen in sources: `R02_xxxx`. R09 naming is unconfirmed.
- Device Information Service `0x180A` is exposed: firmware `0x2A26`, hardware `0x2A27`.

## GATT

| Role | Service | Characteristic |
| :--- | :--- | :--- |
| V1 command write | `6e40fff0-b5a3-f393-e0a9-e50e24dcca9e` | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| V1 notify | `6e40fff0-b5a3-f393-e0a9-e50e24dcca9e` | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |
| V2 big data write | `de5bf728-d711-4e47-af26-65e3012a5dc7` | `de5bf72a-d711-4e47-af26-65e3012a5dc7` |
| V2 big data notify | `de5bf728-d711-4e47-af26-65e3012a5dc7` | `de5bf729-d711-4e47-af26-65e3012a5dc7` |

## V1 framing

Every packet is exactly 16 bytes, both directions.

```
byte 0       command id (bit 7 set on a response means error)
bytes 1..14  payload, zero padded
byte 15      checksum
```

Checksum: sum of bytes 0..14. Puxtril says `& 0xFF`; the tahnok README says
"modulo 255". **Open: settle with the first captured frame.**

Settings commands put an action in byte 1: `1` read, `2` write, `3` delete.

## V2 big data framing

```
byte 0      0xBC (188)
byte 1      data id
bytes 2..3  data length, uint16
bytes 4..5  crc16 (requests send length 0 and crc 0xFFFF)
bytes 6..   payload, may span several notifications
```

| Data id | Content |
| :--- | :--- |
| `0x27` (39) | Sleep, per day: start and end as int16 minutes after midnight, then `{stage, minutes}` pairs |
| `0x2A` (42) | SpO2 |

No temperature data id is documented. Temperature appears only as notify type 5
of command `0x73`. Spike item.

## Commands

| Id | Name | Notes | Status |
| :--- | :--- | :--- | :--- |
| `0x01` | Set date and time | year % 2000, month, day, hour, minute, second | unverified |
| `0x03` | Battery | response: percent, charging flag | unverified |
| `0x08` | Power off | Puxtril calls id 8 "reboot"; test with care | unverified |
| `0x15` | Heart rate log | request carries a unix time; multi-packet response | unverified |
| `0x16` | Auto heart rate setting | read / write interval | unverified |
| `0x2C` | Auto SpO2 setting | | unverified |
| `0x36` | Auto stress setting | | unverified |
| `0x37` | Stress log | | unverified |
| `0x38` | Auto HRV setting | | unverified |
| `0x39` | HRV log | | unverified |
| `0x43` | Activity log | day index | unverified |
| `0x48` | Today's activity totals | | unverified |
| `0x44` | Legacy sleep | superseded by big data `0x27` | unverified |
| `0x50` | Find device | payload `0x55 0xAA`, green LED for 10 s | unverified |
| `0x69` | Real-time data request | data type: heart rate 6 (Puxtril) or 1 (tahnok client, from memory, recheck), SpO2 3; action start 1, stop 4 | unverified |
| `0x73` | Device notify | pushed by the ring; type 5 carries temperature | unverified |
| `0xBC` | Big data | see V2 framing | unverified |
| `0xFF` | Factory reset | do not send during the spike | unverified |

## Sleep stages (big data 0x27)

| Code | Stage | Source agreement |
| :--- | :--- | :--- |
| 0 | no data | Puxtril |
| 1 | error | Puxtril |
| 2 | light | both |
| 3 | deep | both |
| 4 | REM | Gadgetbridge only |
| 5 | awake | both |

Whether the R09 ever emits code 4 decides whether REM comes from the ring or
from our own estimate. Spike item.
