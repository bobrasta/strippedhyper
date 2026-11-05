#!/bin/sh
# Packages the Linux release bundle into dist/hypermed-<version>-linux-x64.tar.gz.
# The tarball's single top-level dir ("hypermed/") is exactly what gets
# installed — the in-app updater extracts it with --strip-components=1 and
# swaps it in place (lib/services/update_service.dart).
#
# Usage: tool/package_linux.sh <version>     (after flutter build linux --release)
set -e
VERSION="${1:?usage: package_linux.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
STAGE="$ROOT/dist/stage/hypermed"
[ -x "$BUNDLE/bienhypermed" ] || { echo "No release bundle at $BUNDLE — run flutter build linux --release first" >&2; exit 1; }

rm -rf "$ROOT/dist/stage"
mkdir -p "$STAGE"
cp -a "$BUNDLE/." "$STAGE/"
cp "$ROOT/installer/linux/install.sh" "$STAGE/install.sh"
cp "$ROOT/web/icons/Icon-512.png" "$STAGE/hypermed.png"
chmod +x "$STAGE/install.sh" "$STAGE/bienhypermed"

OUT="$ROOT/dist/hypermed-$VERSION-linux-x64.tar.gz"
tar -C "$ROOT/dist/stage" -czf "$OUT" hypermed
rm -rf "$ROOT/dist/stage"
echo "$OUT"
