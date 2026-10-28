#!/bin/bash
# Builds dist/UpdateDoctor-<version>.pkg, which installs /usr/local/bin/updatedoctor.
# Run Scripts/build-release.sh first. The pkg is a product archive with a thank you page.
# Set PKG_SIGN_ID to a Developer ID Installer identity to sign it (optional).
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep macOS metadata (._ files) out of the package payload.
export COPYFILE_DISABLE=1

VERSION=$(sed -nE 's/.*current = "(.*)".*/\1/p' Sources/UpdateDoctorKit/Version.swift)
REPO_URL=$(sed -nE 's/.*repositoryURL = "(.*)".*/\1/p' Sources/UpdateDoctorKit/Version.swift)
IDENTIFIER="com.workprasanth9.UpdateDoctor"
[[ -x dist/updatedoctor ]] || { echo "Run Scripts/build-release.sh first."; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/usr/local/bin" "$WORK/packages" "$WORK/resources"
ditto --noextattr --noqtn dist/updatedoctor "$WORK/root/usr/local/bin/updatedoctor"
chmod 755 "$WORK/root/usr/local/bin/updatedoctor"
xattr -cr "$WORK/root" 2>/dev/null || true

COMPONENT="$WORK/packages/UpdateDoctor-component.pkg"
pkgbuild --root "$WORK/root" --identifier "$IDENTIFIER" --version "$VERSION" \
  --install-location / --filter '\.DS_Store$' "$COMPONENT"

sed -e "s|__VERSION__|${VERSION}|g" -e "s|__REPO_URL__|${REPO_URL}|g" \
  Installer/conclusion.html > "$WORK/resources/conclusion.html"

productbuild --synthesize --package "$COMPONENT" "$WORK/distribution.xml" >/dev/null
python3 - "$WORK/distribution.xml" "$VERSION" <<'PY'
import re, sys
path, version = sys.argv[1], sys.argv[2]
xml = open(path).read()
xml = re.sub(r'\s*<options [^>]*/>', '', xml)
extra = (
    f'\n    <title>UpdateDoctor {version}</title>'
    '\n    <conclusion file="conclusion.html" mime-type="text/html"/>'
    '\n    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>'
    '\n    <domains enable_localSystem="true"/>'
)
xml = re.sub(r'(<installer-gui-script[^>]*>)', lambda m: m.group(1) + extra, xml, count=1)
open(path, 'w').write(xml)
PY

SIGN_ARGS=()
if [[ -n "${PKG_SIGN_ID:-}" ]]; then SIGN_ARGS=(--sign "$PKG_SIGN_ID"); fi
PKG="dist/UpdateDoctor-${VERSION}.pkg"
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
  --package-path "$WORK/packages" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$PKG"
echo "Built $PKG"
pkgutil --payload-files "$PKG" | grep updatedoctor
