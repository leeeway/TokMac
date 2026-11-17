#!/usr/bin/env python3
"""Reject development macOS artifacts before either automatic or manual publishing."""
import hashlib
import json
import re
import sys
from pathlib import Path


def verify(directory: Path, version: str) -> None:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Invalid release version")
    status = json.loads((directory / "macos-release-status.json").read_text())
    filename = f"TokMac-{version}.dmg"
    if (status.get("version") != version or status.get("file") != filename
            or status.get("signing_mode") != "distribution" or status.get("notarized") is not True):
        raise ValueError("macOS artifact is not a signed and notarized distribution build")
    digest = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
    if status.get("sha256") != digest:
        raise ValueError("macOS artifact checksum does not match notarization metadata")
    for name in (f"TokMac-Setup-{version}.exe", "TokMac-Windows-Portable.zip"):
        if not (directory / name).is_file() or (directory / name).stat().st_size == 0:
            raise ValueError(f"Missing Windows package: {name}")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1]), sys.argv[2])
    except (ValueError, OSError, KeyError, IndexError) as error:
        raise SystemExit(f"Release validation failed: {error}")
    print("Signed release packages and macOS digest verified.")
