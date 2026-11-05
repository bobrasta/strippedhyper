#!/bin/sh
# Hypermed for Linux — per-user install (no root needed, so the in-app
# updater can replace it in place). Run from the unpacked tarball:
#   tar -xzf hypermed-<version>-linux-x64.tar.gz && ./hypermed/install.sh
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/hypermed/app"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

mkdir -p "$(dirname "$DEST")" "$BIN" "$APPS"
if [ "$SRC" != "$DEST" ]; then
  rm -rf "$DEST.new"
  cp -a "$SRC" "$DEST.new"
  rm -rf "$DEST"
  mv "$DEST.new" "$DEST"
fi
ln -sf "$DEST/bienhypermed" "$BIN/hypermed"

cat > "$APPS/hypermed.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Hypermed
Comment=Medical equipment, service and sales management
Exec=$DEST/bienhypermed
Icon=$DEST/hypermed.png
StartupWMClass=bienhypermed
Terminal=false
Categories=Office;
DESKTOP

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
echo "Hypermed installed to $DEST"
echo "Launch it from your applications menu, or run: hypermed"
