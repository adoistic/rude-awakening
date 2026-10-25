#!/usr/bin/env bash
# Installs the latest Rude Awakening release.
#   curl -fsSL https://raw.githubusercontent.com/adoistic/rude-awakening/main/install.sh | bash
set -euo pipefail

REPO="adoistic/rude-awakening"
APP="Rude Awakening.app"

echo "⏰ Installing Rude Awakening…"

if [ "$(uname)" != "Darwin" ]; then
  echo "✗ This is a Mac app. Nice try." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$major" -lt 14 ]; then
  echo "✗ Needs macOS 14 Sonoma or newer (you have $(sw_vers -productVersion))." >&2
  exit 1
fi

url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d'"' -f4)"
if [ -z "$url" ]; then
  echo "✗ Couldn't find a release to download. Grab it from https://github.com/$REPO/releases" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "$url" -o "$tmp/app.zip"
ditto -x -k "$tmp/app.zip" "$tmp"

dest="/Applications"
[ -w "$dest" ] || dest="$HOME/Applications"
mkdir -p "$dest"

osascript -e 'tell application "Rude Awakening" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "${dest:?}/$APP"
mv "$tmp/$APP" "$dest/"
# The app is open source and not notarised by Apple; this tells Gatekeeper you meant to install it.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

open "$dest/$APP"
echo "✓ Installed to $dest. Paste your OpenRouter key when it asks. That's the whole setup."
