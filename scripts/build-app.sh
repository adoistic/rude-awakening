#!/usr/bin/env bash
# Builds "Rude Awakening.app" into dist/. Needs only the Xcode Command Line Tools.
#
#   scripts/build-app.sh            build a universal (Apple silicon + Intel) app
#   scripts/build-app.sh --install  also copy it to /Applications and open it
#   scripts/build-app.sh --zip      also make dist/Rude-Awakening-<version>.zip for a release
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="Rude Awakening"
EXECUTABLE="RudeAwakening"
BUNDLE_ID="com.thothica.RudeAwakening"
VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Building $APP_NAME $VERSION ($BUILD_NUMBER)"

# One build per architecture, then glue them together. (Multi-arch in one go needs full Xcode.)
BINARIES=()
for ARCH in arm64 x86_64; do
  echo "  · compiling for $ARCH"
  if swift build -c release --product "$EXECUTABLE" --triple "$ARCH-apple-macosx14.0" >/tmp/rude-build-$ARCH.log 2>&1; then
    BINARIES+=("$(swift build -c release --product "$EXECUTABLE" --triple "$ARCH-apple-macosx14.0" --show-bin-path)/$EXECUTABLE")
  else
    echo "    (skipped $ARCH: see /tmp/rude-build-$ARCH.log)"
  fi
done
if [ ${#BINARIES[@]} -eq 0 ]; then
  echo "✗ Build failed." >&2
  cat /tmp/rude-build-arm64.log >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$EXECUTABLE"
echo "  · architectures: $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")"

echo "  · drawing the icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Adnan. MIT License.</string>
</dict>
</plist>
PLIST

echo "  · signing (ad hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify "$APP"

echo "✓ $APP"

for arg in "$@"; do
  case "$arg" in
    --zip)
      ZIP="$DIST/Rude-Awakening-$VERSION.zip"
      rm -f "$ZIP"
      (cd "$DIST" && ditto -c -k --keepParent "$APP_NAME.app" "$(basename "$ZIP")")
      echo "✓ $ZIP"
      ;;
    --install)
      osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
      sleep 1
      rm -rf "/Applications/$APP_NAME.app"
      cp -R "$APP" "/Applications/"
      echo "✓ installed to /Applications"
      open "/Applications/$APP_NAME.app"
      ;;
  esac
done
