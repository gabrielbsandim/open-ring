# Protocol Reverse Engineering: Colmi R09 (Realsil RTL8762)

Technical specification of the BLE communication protocol between the smartphone and the Colmi R09 (marketed as "COLMI Ring 2") running firmware `3.00.03`.

## 1. Hardware Architecture

* **SoC / MCU**: Realtek (Realsil) RTL8762D / RTL8762E Series (Bluetooth 5.2 Low Energy SoC, ARM Cortex-M4F core, embedded 160KB RAM, external SPI NOR Flash).
* **Sensors**:
  * PPG Optical Heart Rate Sensor (dual green + infrared LED, photodiode).
  * 3-Axis Accelerometer (step counting, motion detection, sleep posture).
  * High-precision NTC contact temperature sensor.
* **Storage**: Onboard flash buffer storing up to 7 days of raw step buckets and sleep interval blocks.

---

## 2. Bluetooth GATT Architecture

### 1. Advertisement Data
* **Device Name**: `COLMI Ring 2` (or `QRing`, `R09_*`).
* **MAC Format**: Standard 48-bit address (e.g., `AA:BB:CC:DD:EE:FF`).

### 2. Primary GATT Services & Characteristics

| Service UUID | Characteristic UUID | Properties | Purpose |
| :--- | :--- | :--- | :--- |
| `0000fee7-0000-1000-8000-00805f9b34fb` | `0000fea1-0000-1000-8000-00805f9b34fb` | Write, Write Without Response | **TX (Phone -> Ring)**: Command dispatch. |
| `0000fee7-0000-1000-8000-00805f9b34fb` | `0000fea2-0000-1000-8000-00805f9b34fb` | Notify, Read | **RX (Ring -> Phone)**: Telemetry stream and responses. |
| `0000180a-0000-1000-8000-00805f9b34fb` | `00002a26-0000-1000-8000-00805f9b34fb` | Read | Firmware Version string (`3.00.03`). |
| `0000180a-0000-1000-8000-00805f9b34fb` | `00002a28-0000-1000-8000-00805f9b34fb` | Read | Software Revision string. |
| `0000180f-0000-1000-8000-00805f9b34fb` | `00002a19-0000-1000-8000-00805f9b34fb` | Read, Notify | Standard Battery Level percentage (0-100%). |

*Note: Some hardware revisions also expose the Realtek OTA Service (`000002fd-3c17-d293-8e48-14fe2e4da212`) for firmware upgrades.*

---

## 3. Packet Framing & Protocol Details

Packets sent between phone and ring follow a fixed 16 or 20-byte payload structure.

### 1. General Packet Structure

```
+--------+--------+--------+--------+------------------+----------+
| Byte 0 | Byte 1 | Byte 2 | Byte 3 | Bytes 4..N-1     | Byte N   |
+--------+--------+--------+--------+------------------+----------+
| Header | Cmd ID | SubCmd | Length | Payload Data     | Checksum |
+--------+--------+--------+--------+------------------+----------+
```

* **Header**: Typically `0xAB` (Command) or `0xAA` (Response).
* **Length**: Number of payload bytes.
* **Checksum**: Simple sum modulo 256 (`(sum(bytes[0..N-1])) & 0xFF`).

### 2. Core Command Set

#### Time Synchronization (Handshake Step 1)
Sent immediately after connection so the ring can accurately timestamp internal sensor events:
* **Command ID**: `0x01`
* **Payload**: `[Year - 2000, Month, Day, Hour, Minute, Second]`

#### Read Battery & Device State
* **Command ID**: `0x03`
* **Response**: Returns battery percentage, charging state (0=Discharging, 1=Charging, 2=Full).

#### Sync Daily Summary (Steps, Calories, Distance)
* **Command ID**: `0x07`
* **Payload**: Date to query (`[Year, Month, Day]`).
* **Response**: Total steps (4 bytes big-endian), total calories (4 bytes), total distance (4 bytes in decimeters).

#### Sync Sleep History
The ring records sleep periods into flash in segments.
* **Command ID**: `0x15` (Subcommand `0x01` for sleep index query).
* **Response Structure**:
  * Start timestamp (epoch or date/time structure).
  * End timestamp.
  * Array of sleep blocks: duration (minutes) + sleep stage flag (`0x01` = Deep Sleep, `0x02` = Light Sleep, `0x03` = Awake, `0x04` = REM).

#### Real-time Heart Rate Stream (Live PPG)
* **Start Live Measurement**: `0x09 0x01` (Ring turns on green LED and transmits continuous bpm samples).
* **Stop Live Measurement**: `0x09 0x00`.

#### Real-time SpO2 Stream
* **Start SpO2 Measurement**: `0x11 0x01` (Ring turns on red and infrared LEDs).
* **Stop SpO2 Measurement**: `0x11 0x00`.

#### Skin Temperature Read
* **Command ID**: `0x14`
* **Response**: Temperature in hundredths of a degree Celsius (e.g. `3650` = 36.50 °C).
