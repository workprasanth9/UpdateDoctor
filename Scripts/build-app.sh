#!/bin/bash
# Builds dist/UpdateDoctor.app: the menu bar app with the updatedoctor CLI bundled
# in Contents/Resources (used for "Run full check (admin)" and by the Homebrew cask).
# Usage: ./Scripts/build-app.sh [--universal]
# Without --universal the build is for the host architecture (Command Line Tools only).
# Signed ad hoc with the hardened runtime. Not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/.*current = "(.*)".*/\1/p' Sources/UpdateDoctorKit/Version.swift)
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
else
  ARCH_ARGS=()
fi
swift build -c release --product UpdateDoctorApp ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
swift build -c release --product updatedoctor ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)

APP=dist/UpdateDoctor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/UpdateDoctorApp" "$APP/Contents/MacOS/UpdateDoctor"
cp "$BIN_DIR/updatedoctor" "$APP/Contents/Resources/updatedoctor"
chmod 755 "$APP/Contents/MacOS/UpdateDoctor" "$APP/Contents/Resources/updatedoctor"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/${VERSION}/g" App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
xattr -cr "$APP" 2>/dev/null || true

codesign --force --options runtime --timestamp=none --sign - "$APP/Contents/Resources/updatedoctor"
codesign --force --options runtime --timestamp=none --sign - "$APP"
codesign --verify --strict --verbose=1 "$APP"
lipo -info "$APP/Contents/MacOS/UpdateDoctor"
echo "Built $APP ($VERSION)"
