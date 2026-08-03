#!/usr/bin/env python3
"""Generate a TourBox Max/MSP preset and repair missing C1/C2 bindings."""

from __future__ import annotations

import argparse
import base64
import gzip
from pathlib import Path
import re
import zipfile


LEGACY_JAR_PATH = Path(
    "/Applications/TourBox Console.app/Contents/Resources/TourBox_mac.jar"
)
LEGACY_TEMPLATE_PATH = "com/tourbox/plugin/max/Max_MacOS_zh_CN.tb"
DEFAULT_NAME = "Codex Micro Advanced"
CONFIG_PATTERN = re.compile(rb"(<configBytes>)([^<]+)(</configBytes>)")
NAME_PATTERN = re.compile(rb"(<presetName>)([^<]*)(</presetName>)")

# TourBox's preset payload contains a two-byte header, one metadata record,
# then a 13-byte record for every event code. The last four bytes of a button
# record select its output action. Current TourBox Console versions adapt the
# legacy Max preset to the connected device, but leave Elite C1/C2 unassigned.
HEADER_SIZE = 2
RECORD_SIZE = 13
EVENT_RECORD_BIAS = 1
EVENT_ID_OFFSET = 7
ACTION_OFFSET = 9
ACTION_SIZE = 4
C1_CODE = 34
C2_CODE = 35
REFERENCE_BUTTON_CODE = 0  # Tall, already bound to Max/MSP by TourBox Console.


def read_preset(source: Path | None) -> bytes:
    if source is not None:
        return source.read_bytes()
    if not LEGACY_JAR_PATH.exists():
        raise RuntimeError(
            "This TourBox Console version no longer bundles the legacy Max preset. "
            "Pass --source with an exported or imported Max/MSP .tb preset."
        )
    with zipfile.ZipFile(LEGACY_JAR_PATH) as archive:
        return archive.read(LEGACY_TEMPLATE_PATH)


def record_start(code: int) -> int:
    return HEADER_SIZE + (code + EVENT_RECORD_BIAS) * RECORD_SIZE


def repair_max_bindings(compressed_preset: bytes, name: str) -> bytes:
    xml = gzip.decompress(compressed_preset)
    match = CONFIG_PATTERN.search(xml)
    if match is None:
        raise RuntimeError("The source preset has no configBytes payload")

    config = bytearray(base64.b64decode(match.group(2), validate=True))
    required_size = record_start(255) + RECORD_SIZE
    if len(config) < required_size:
        raise RuntimeError(f"Unexpected TourBox config size: {len(config)} bytes")

    reference_start = record_start(REFERENCE_BUTTON_CODE)
    reference = config[reference_start : reference_start + RECORD_SIZE]
    if reference[EVENT_ID_OFFSET] != REFERENCE_BUTTON_CODE:
        raise RuntimeError("Unexpected TourBox event-record layout")
    max_action = reference[ACTION_OFFSET : ACTION_OFFSET + ACTION_SIZE]
    if not any(max_action):
        raise RuntimeError(
            "The source preset has not been adapted to a device or its Tall button "
            "is not assigned to Max/MSP. Import it in TourBox Console first, then "
            "use the copy under TourBox Console/import as --source."
        )

    for code in (C1_CODE, C2_CODE):
        start = record_start(code)
        record = config[start : start + RECORD_SIZE]
        if record[EVENT_ID_OFFSET] != code:
            raise RuntimeError(f"Unexpected record for TourBox event {code}")
        config[start + ACTION_OFFSET : start + ACTION_OFFSET + ACTION_SIZE] = max_action

    encoded = base64.b64encode(config)
    xml = xml[: match.start(2)] + encoded + xml[match.end(2) :]

    name_match = NAME_PATTERN.search(xml)
    if name_match is None:
        raise RuntimeError("The source preset has no presetName")
    encoded_name = name.encode("utf-8")
    xml = xml[: name_match.start(2)] + encoded_name + xml[name_match.end(2) :]
    return gzip.compress(xml, compresslevel=9, mtime=0)


def verify_bindings(compressed_preset: bytes) -> None:
    xml = gzip.decompress(compressed_preset)
    match = CONFIG_PATTERN.search(xml)
    if match is None:
        raise RuntimeError("Generated preset has no configBytes payload")
    config = base64.b64decode(match.group(2), validate=True)
    reference_start = record_start(REFERENCE_BUTTON_CODE)
    expected = config[
        reference_start + ACTION_OFFSET : reference_start + ACTION_OFFSET + ACTION_SIZE
    ]
    for label, code in (("C1", C1_CODE), ("C2", C2_CODE)):
        start = record_start(code)
        actual = config[start + ACTION_OFFSET : start + ACTION_OFFSET + ACTION_SIZE]
        if actual != expected or not any(actual):
            raise RuntimeError(f"Generated preset did not bind {label} to Max/MSP")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--name", default=DEFAULT_NAME)
    arguments = parser.parse_args()

    generated = repair_max_bindings(read_preset(arguments.source), arguments.name)
    verify_bindings(generated)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(generated)
    print(f"Generated {arguments.output}")
    print("Verified Max/MSP bindings: C1 event 34, C2 event 35")


if __name__ == "__main__":
    main()
