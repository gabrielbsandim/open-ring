# trace_replay

Dart CLI for the JSONL sessions that the protocol lab in `apps/mobile` exports.
It decodes every frame with `packages/ring_protocol` and replays recorded syncs
through `ColmiDriver` from `packages/ring_driver`, offline.

## Input

One JSON object per line, as `FrameLogEntry.toJson` writes it:

```json
{"t":"2024-08-10T23:58:00.000Z","dir":"rx","char":"6e400003-b5a3-f393-e0a9-e50e24dcca9e","hex":"03400000000000000000000000000043"}
```

`t` is ISO-8601 (the app writes UTC), `dir` is `tx` or `rx`, `char` is the GATT
characteristic UUID and `hex` the raw bytes. Blank lines are skipped. A line
that does not parse is reported with its line number and the reason, and the
rest of the file is still processed.

## Usage

Run from the workspace root (`dart pub get` once):

```sh
dart run tools/trace_replay/bin/trace_replay.dart decode session.jsonl
dart run tools/trace_replay/bin/trace_replay.dart replay session.jsonl --now 2024-08-10T23:59
```

### decode

Prints each frame as line number, time, direction, channel and raw hex, then:

- `checksum:` for every 16 byte V1 frame (tx and rx), checked under both
  candidate rules from `docs/protocols/realsil-colmi.md`: masked (`& 0xFF`)
  and modulo 255 (`% 255`). It says whether the frame passes both, only one
  (and what the other rule expects), or neither.
- the decoded meaning, or `FAILED:` with the reason: wrong length, checksum
  failing both rules, error response (bit 7), unknown command or
  characteristic, big data CRC mismatch, parser errors.

Multi frame replies (heart rate, stress, HRV and activity logs, V2 big data
chunks) are assembled in trace order and print the full record on the frame
that completes them.

The summary counts frames per checksum outcome and names the rule that every
V1 frame satisfies: one rule, `both (no frame tells them apart)` while no frame
sums past 254, or `none` when some frame fails both.

### replay

Splits the trace into exchanges (a tx and the rx frames up to the next tx),
then calls the `ColmiDriver` method behind each recorded request against a
`FakeBleTransport` that answers each driver write with the recorded replies.
A write is matched to the first unused exchange with the same body, then to
the first with the same command (and data id for big data). Consecutive
activity, heart rate or HRV requests for different days become one call that
spans that many days.

Replayed calls: `syncTime`, `readBattery`, `findDevice`, `pullActivity`,
`pullHeartRate`, `pullStress`, `pullHrv`, `pullSpo2`, `pullSleep`. Any other
tx is listed as `not replayed`. A step whose replies are missing, truncated or
invalid prints `FAILED:` with the reason and the replay goes on.

Options:

| Option | Default | Meaning |
|--------|---------|---------|
| `--checksum masked\|mod255` | detected | V1 checksum rule of the driver codec. Detected from the rx frames: modulo 255 only when more rx frames pass only that rule. |
| `--now <ISO-8601>` | each request's `t` in this machine's zone | Driver clock. Without an offset it is local time. The driver dates records and drops future slots from this clock, so pass the time of the recording when the trace came from another time zone. |
| `--timeout <ms>` | `1000` | How long the driver waits for a complete reply. |

Exit codes: `0` done (frame or step failures are part of the output), `64`
usage error, `66` file not readable.

## Tests

From `tools/trace_replay`:

```sh
dart test
```

The fixtures in
`test/fixtures` are built from frames already used in the `ring_protocol` and
`ring_driver` tests (tahnok captures and the Gadgetbridge layouts):

- `heart_rate_sync.jsonl`: set time, battery with a device notify push, the
  tahnok heart rate log, a stress log and find device.
- `activity_big_data.jsonl`: the tahnok activity capture and big data SpO2,
  sleep and temperature split over several notifications.
- `checksum_cases.jsonl`: frames for each checksum outcome, an error response,
  unknown command and characteristic, a short frame, a CRC mismatch and two
  malformed lines.
