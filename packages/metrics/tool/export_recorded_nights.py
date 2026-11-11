"""Writes the sleep and heart rate rows of an app database to a JSON file.

Usage: python3 -I export_recorded_nights.py <open_ring.sqlite> <output.json>

The output is personal health data. Keep it outside the repository.
"""

import json
import os
import sqlite3
import sys

SPANS = """
    select start_utc_ms, end_utc_ms, offset_minutes, stage
    from sleep_segments order by start_utc_ms
"""
HEART_RATE = "select at_utc_ms, bpm from hr_samples order by at_utc_ms"


def recording(database_path):
    connection = sqlite3.connect(f"file:{database_path}?mode=ro", uri=True)
    return {
        "spans": [
            {"startUtcMs": s, "endUtcMs": e, "offsetMinutes": o, "stage": t}
            for s, e, o, t in connection.execute(SPANS)
        ],
        "heartRate": [
            {"atUtcMs": at, "bpm": bpm}
            for at, bpm in connection.execute(HEART_RATE)
        ],
    }


def main(database_path, output_path):
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(recording(database_path), output)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
