#!/usr/bin/env python3
"""Writes the update feed (latest.json) the app polls — see
lib/services/update_service.dart (UpdateManifest) for the reader.

Usage:
  tool/make_update_manifest.py --version 1.4.0 --base-url https://app.hypermed.co.tz/updates \
      --windows dist/Hypermed-Setup-1.4.0.exe --linux dist/hypermed-1.4.0-linux-x64.tar.gz \
      [--min-version 1.2.0] [--notes-file notes.txt] --out dist/latest.json

--min-version defaults to the contents of release/min_version.txt: any app
older than it is blocked behind "Update required" until it updates.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib


def asset(path, base_url):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    name = os.path.basename(path)
    return {"url": f"{base_url.rstrip('/')}/{name}", "sha256": h.hexdigest(), "size": os.path.getsize(path)}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True)
    p.add_argument("--base-url", required=True)
    p.add_argument("--windows")
    p.add_argument("--linux")
    p.add_argument("--min-version")
    p.add_argument("--notes-file")
    p.add_argument("--out", required=True)
    a = p.parse_args()

    min_version = a.min_version
    if not min_version:
        f = pathlib.Path(__file__).resolve().parent.parent / "release" / "min_version.txt"
        min_version = f.read_text().strip() if f.exists() else None

    notes = pathlib.Path(a.notes_file).read_text().strip() if a.notes_file else ""
    platforms = {}
    if a.windows:
        platforms["windows"] = asset(a.windows, a.base_url)
    if a.linux:
        platforms["linux"] = asset(a.linux, a.base_url)

    manifest = {
        "version": a.version,
        "min_version": min_version,
        "notes": notes,
        "released_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "platforms": platforms,
    }
    pathlib.Path(a.out).write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
