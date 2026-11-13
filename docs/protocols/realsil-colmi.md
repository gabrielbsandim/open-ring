# Colmi Ring BLE Protocol

Status: compiled on 2026-11-10 from open implementations. Phase 1 marks each
row verified on an R09 or dropped; `packages/ring_protocol/lib/src/status.dart`
holds the same verdicts.

The previous version of this file listed service `0000fee7` with characteristics
`fea1`/`fea2`, an `0xAB`/`0xAA` header and commands `0x07`, `0x09`, `0x11`, `0x14`.
None of those appear in any source below, so they were removed.

## Sources

- Gadgetbridge, `devices/colmi/ColmiR0xConstants.java` (Freeyourgadget/Gadgetbridge, master).
  On master (2026-11) these moved to `devices/yawell/ring/YawellRingConstants.java`,
  `devices/yawell/ring/YawellRingPacketHandler.java` and
  `service/devices/yawell/ring/YawellRingDeviceSupport.java`; the R09 coordinator
  is `devices/yawell/ring/ColmiR09Coordinator.java`.
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

Checksum: sum of bytes 0..14, masked with `& 0xFF`. **Settled on 2026-11-10
on an R09** ("COLMI Ring 2", firmware not yet read): the heart rate log reply
`15 01 80 5e f2 6a 49 00 .. 00 99` sums to 665, which is `0x99` masked and
`0x9b` modulo 255. The ring does not validate the checksum it receives: find
device lit the LED with both `..4f` and `..50`. The tahnok README says
"modulo 255"; the earlier evidence, not from our ring: tahnok `colmi_r02_client/packet.py` computes `sum(packet) & 255`
despite its README, Gadgetbridge `buildPacket` masks with `& 0xff`, and the R02
capture `43 23 08 13 14 01 05 b6 18 aa 04 69 03 00 00 83` in tahnok
`tests/test_steps.py` sums to 643, which is `0x83` masked and `0x85` modulo 255.

Settings commands put an action in byte 1: `1` read, `2` write, `3` delete.

## V2 big data framing

```
byte 0      0xBC (188)
byte 1      data id
bytes 2..3  payload length, uint16 little endian
bytes 4..5  crc16 of the payload, little endian
bytes 6..   payload, may span several notifications
```

The crc16 is CRC-16/MODBUS (poly `0xA001` reflected, init `0xFFFF`, no final
xor), per Gadgetbridge `YawellRingPacketHandler.crc16Modbus`. Gadgetbridge never
checks it on responses. Verified on an R09: the ring fills it, and every sleep
and SpO2 reply passes the check.

Requests: Puxtril sends an empty payload (`BC 27 00 00 FF FF`). Gadgetbridge
`fetchHistorySleep` and `fetchHistorySpo2` send one `0xFF` byte
(`BC 27 01 00 FF 00 FF`); `fetchTemperature` sends `0x02` (`BC 25 01 00 3E 81 02`).
Both forms are the same encoder, since the CRC of an empty payload is `0xFFFF`.
The one `0xFF` byte form is verified on an R09; the empty form is untried.
A response is complete once `6 + length` bytes have arrived
(`YawellRingDeviceSupport.onCharacteristicChanged`).

| Data id | Content |
| :--- | :--- |
| `0x25` (37) | Temperature (Gadgetbridge only), see below. Dropped for v1: the meaning of its first byte and the accuracy of the value are unverified on an R09 |
| `0x27` (39) | Sleep, per day: start and end as int16 minutes after midnight, then `{stage, minutes}` pairs |
| `0x2A` (42) | SpO2 |

Payload layouts (offsets from byte 6):

- Sleep `0x27` (`YawellRingPacketHandler.historicalSleep`, Puxtril `SleepData`):
  day count, then per day `daysAgo`, `dayBytes`, start and end (2 bytes each,
  little endian), then `(dayBytes - 4) / 2` pairs `{stage, minutes}`. One day
  takes `2 + dayBytes` bytes. Gadgetbridge reads start and end unsigned and treats
  `start > end` as "started the evening before"; Puxtril types them `int16`.
  Verified on an R09: a night parsed this way had the same start and end that
  QRing wrote to Health Connect.
- SpO2 `0x2A` (`historicalSpo2`): per day `daysAgo`, then 24 hourly
  `{min, max}` pairs; Gadgetbridge stores the rounded mean. Puxtril
  `BloodOxygenData` puts an unknown byte before `daysAgo`.
  Verified on an R09 with the Gadgetbridge layout: the day range, 96 to 99,
  matched QRing.
- Temperature `0x25` (`historicalTemperature`): per day `daysAgo`, one unknown
  byte (always `0x1E` so far), then 48 half hourly bytes; a non zero byte is
  `byte / 10 + 20` degrees C.

Temperature also appears as notify type 5 of command `0x73`, whose payload no
source documents. Spike item.

## Commands

| Id | Name | Notes | Status |
| :--- | :--- | :--- | :--- |
| `0x01` | Set date and time | year % 2000, month, day, hour, minute, second, each BCD (tahnok `byte_to_bcd`, Gadgetbridge parses the decimal string as hex); tahnok adds byte 7 language (1 English). Reply: capability flags | verified on an R09: the reply carried capability flags (temperature, SpO2, new sleep protocol, stress, HRV) and heart rate slots align with QRing |
| `0x03` | Battery | response: percent, charging flag | verified on an R09 |
| `0x08` | Power off | Puxtril calls id 8 "reboot"; test with care | dropped: v1 never powers the ring off |
| `0x15` | Heart rate log | request carries a uint32 LE time: local midnight as if UTC (Gadgetbridge, Puxtril) or real UTC (tahnok); multi-packet response, see below | verified on an R09: local wall clock encoded as UTC; the day range matched QRing |
| `0x16` | Auto heart rate setting | `{action, enabled, minutes}`; enabled 1 on, 2 off (tahnok `hr_settings.py`) | verified on an R09: writing 5 minutes gave 5 minute heart rate slots. After writing 10 minutes the ring read back `16 01 01 0a 05` (byte 4 unknown) and the log kept 5 minute slots with a reading in every second one: 5 readings in the 50 minutes after the write (`settings_test.dart`, `slot_log_test.dart`) |
| `0x1E` | Continuous heart rate | Gadgetbridge `CMD_REALTIME_HEART_RATE` (`onEnableRealtimeHeartRateMeasurement`): enable `{0x01}`, disable `{0x02}`. Reply `{bpm, ...}` about once a second; the ring stops after 60 s unless a continue `{0x03}` arrives, and Gadgetbridge sends one every 30 replies and drops a reply in the same second as the previous one (`YawellRingPacketHandler.realtimeHeartRate`). Used for live workouts | verified on an R09: a continue every 20 s kept 121 readings in 120 s, largest gap 1.2 s |
| `0x2C` | Auto SpO2 setting | `{action, enabled}`; Gadgetbridge writes 1 on, 0 off | verified on an R09: a read (action 1) returned enabled 1 |
| `0x36` | Auto stress setting | as `0x2C` | verified on an R09: a read returned enabled 1 |
| `0x37` | Stress log | Gadgetbridge sends the bare id; Puxtril names byte 1 "index". Response as HRV log | verified on an R09: latest 43, range 30 to 65 and mean 42 matched QRing |
| `0x38` | Auto HRV setting | as `0x2C` | verified on an R09: a read returned enabled 1 |
| `0x39` | HRV log | byte 1 days ago (Gadgetbridge `fetchHistoryHRV`); multi-packet, see below | verified on an R09: latest 44 ms matched QRing |
| `0x43` | Activity log | request `{daysAgo, 0x0F, 0x00, 0x5F, 0x01}`; see below | verified on an R09: 1920 steps, 1.31 km and 74 kcal matched QRing |
| `0x48` | Today's activity totals | Puxtril only: total steps, running steps, calories, walking distance (24 bit each), active minutes (16 bit); byte order not stated | verified on an R09: big endian, calories in cal; 2144 steps, 1471 m and 83.8 kcal at 16:34 against 2079 steps, 1424 m and 81.1 kcal in the `0x43` buckets synced to 16:15 |
| `0x44` | Legacy sleep | superseded by big data `0x27` | dropped: big data `0x27` is verified |
| `0x50` | Find device | payload `0x55 0xAA`, green LED for 10 s | verified on an R09: the LED lit |
| `0x69` | Real-time data request | `{type, action}`; type heart rate 1 (tahnok `real_time.py`, Gadgetbridge `onHeartRateTest`; Puxtril lists 1 and also 6 "RealtimeHeartRate"), SpO2 3; action start 1, pause 2, continue 3, stop 4. Reply `{type, error, value}`. One-shot: used for spot measures, not for a stream | verified on an R09: one reading per start, HR 81 and SpO2 98 |
| `0x6A` | Stop real-time data | tahnok `get_stop_packet` stops with `0x6A {type, 0, 0}` instead of `0x69` action 4 | verified on an R09: the ring acknowledged `{1, 0, 0}` and sent no further reading |
| `0x73` | Device notify | pushed by the ring; byte 1 type: 1 HR, 3 SpO2, 4 steps "new data", 5 temperature (Puxtril), `0x0C` battery `{percent, charging}`, `0x12` live activity: steps, calories, distance as 24 bit big endian (Gadgetbridge `liveActivity`) | verified on an R09 for type 1 (new heart rate data); the other types follow the sources |
| `0xBC` | Big data | see V2 framing | verified on an R09: sleep and SpO2 replies |
| `0xFF` | Factory reset | do not send during the spike | dropped: v1 never resets the ring |

## Multi-packet V1 responses

Byte 1 is the packet index. `0xFF` means no data.

- Heart rate `0x15` (Puxtril, tahnok `hr.py`, Gadgetbridge): index 0 carries
  the packet count (byte 2) and the slot length in minutes (byte 3, 5 so far, also after a 10 minute `0x16` write);
  index 1 carries a uint32 LE time in bytes 2..5 and 9 values; every later index
  carries 13 values in bytes 2..14. Slots start at midnight. The ring does not
  clear slots later than now for today (Gadgetbridge drops them, tahnok zeroes
  them).
- Stress `0x37` and HRV `0x39` (Gadgetbridge `historicalStress`,
  `historicalHRV`): index 0 carries the packet count; index 1 has an unknown
  byte 2 and 12 values in bytes 3..14; later indexes carry 13 values in bytes
  2..14; slots are 30 minutes. Puxtril agrees for HRV but shows stress packets
  after index 1 as one offset byte plus 12 values.
- Activity `0x43` (tahnok `steps.py`, Gadgetbridge `historicalActivity`):
  a `0xF0` header whose byte 3 = 1 means "new calorie protocol" (tahnok
  multiplies calories by 10); then one packet per quarter hour: year, month, day
  as BCD, quarter of the day (0..95), packet index, packet count, calories,
  steps, distance in meters (uint16 LE each). Gadgetbridge drops the quarter
  inside the hour (`value[4] / 4`) and does not apply the x10.
  Verified on an R09: with the x10 applied, calories are in cal, and the day
  summed to the 74 kcal QRing showed.

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
