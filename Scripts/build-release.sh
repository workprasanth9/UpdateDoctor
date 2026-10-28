#!/bin/bash
# Builds the updatedoctor release binary into dist/ as a .tar.gz and a .zip.
# Pass --universal (needs full Xcode, as on GitHub Actions) for arm64 + x86_64.
# With only the Command Line Tools, the build is for the host architecture.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/.*current = "(.*)".*/\1/p' Sources/UpdateDoctorKit/Version.swift)
mkdir -p dist
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
  SUFFIX="universal"
else
  ARCH_ARGS=()
  SUFFIX=$(uname -m)
fi
swift build -c release --product updatedoctor ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)

rm -f dist/updatedoctor
cp "$BIN_DIR/updatedoctor" dist/updatedoctor
# Ad hoc signature (no Apple Developer ID). Fine for Homebrew, pkg and Jamf installs.
codesign --force --sign - dist/updatedoctor
lipo -info dist/updatedoctor
export COPYFILE_DISABLE=1
( cd dist && tar -czf "updatedoctor-${VERSION}-macos-${SUFFIX}.tar.gz" updatedoctor \
          && rm -f "updatedoctor-${VERSION}-macos-${SUFFIX}.zip" \
          && zip -q "updatedoctor-${VERSION}-macos-${SUFFIX}.zip" updatedoctor )
echo "Built dist/updatedoctor-${VERSION}-macos-${SUFFIX}.tar.gz and .zip"
