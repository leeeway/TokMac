#!/usr/bin/env python3
"""Require notarization by default; permit verified development builds only by manual opt-in."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


def verify(directory: Path, version: str, allow_unnotarized: bool = False) -> None:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Invalid release version")
    status = json.loads((directory / "macos-release-status.json").read_text())
    filename = f"TokMac-{version}.dmg"
    notarized = status.get("signing_mode") == "distribution" and status.get("notarized") is True
    development = status.get("signing_mode") == "development" and status.get("notarized") is False
    if (status.get("version") != version or status.get("file") != filename
            or not (notarized or (allow_unnotarized and development))):
        raise ValueError("macOS artifact is not a signed and notarized distribution build")
    digest = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
    if status.get("sha256") != digest:
        raise ValueError("macOS artifact checksum does not match notarization metadata")
    for name in (f"TokMac-Setup-{version}.exe", "TokMac-Windows-Portable.zip"):
        if not (directory / name).is_file() or (directory / name).stat().st_size == 0:
            raise ValueError(f"Missing Windows package: {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("version")
    parser.add_argument("--allow-unnotarized", action="store_true",
                        help="Explicit manual release of an ad-hoc build; never used by automatic publishing")
    args = parser.parse_args()
    try:
        verify(args.directory, args.version, args.allow_unnotarized)
    except (ValueError, OSError, KeyError, IndexError) as error:
        raise SystemExit(f"Release validation failed: {error}")
    print("Release packages and macOS digest verified.")
