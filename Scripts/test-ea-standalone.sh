#!/bin/bash
# Fixture tests for Jamf/updatedoctor-ea-standalone.sh. No root, MDM or network needed.
# Each case copies Tests/ea-standalone/base, changes one thing, and checks the <result> line.
set -u
cd "$(dirname "$0")/.." || exit 1
EA="Jamf/updatedoctor-ea-standalone.sh"
BASE="Tests/ea-standalone/base"
NOW_EPOCH=1793810400   # 2026-11-04 12:00 UTC
PASS=0
FAIL=0
WORK=$(mktemp -d /tmp/ud-ea-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

su_set() { /usr/bin/plutil -replace "$1" "$2" "$3" "$WORK/fx/SoftwareUpdate.plist"; }

# run_case NAME ROOT SETUP EXPECT... : EXPECT is an extended regex that must match;
# a leading ! means it must not match.
run_case() {
  local name="$1" root="$2" setup="$3" out pat ok=1
  shift 3
  rm -rf "$WORK/fx"; cp -R "$BASE" "$WORK/fx"
  eval "$setup"
  out=$(UD_FIXTURES="$WORK/fx" UD_NOW=$NOW_EPOCH UD_AS_ROOT="$root" /bin/bash "$EA")
  for pat in "$@"; do
    case "$pat" in
      !*) if echo "$out" | grep -qE -- "${pat#!}"; then ok=0; echo "  unexpected: ${pat#!}"; fi ;;
      *) if ! echo "$out" | grep -qE -- "$pat"; then ok=0; echo "  missing: $pat"; fi ;;
    esac
  done
  if [ $ok = 1 ]; then PASS=$((PASS + 1)); echo "ok   $name"
  else FAIL=$((FAIL + 1)); echo "FAIL $name"; echo "  output: $out"; fi
}

run_case "healthy, root, enrolled" 1 ":" \
  '^<result>HEALTHY \| info: macOS 26.7.2 \(25G332\), FileVault on \| ud-sh [0-9.]+</result>$' '!skipped'
run_case "single line, Jamf tags once" 1 ":" '^<result>[^<>]*</result>$'
run_case "behind latest in same major" 1 "printf 'ProductVersion: 26.7\nBuildVersion: 25G229\n' > \$WORK/fx/sw_vers.txt" \
  '^<result>AT_RISK' 'warn: os_version \(26.7 behind 26.7.2\)' '!26.8'
run_case "GDMF unreadable" 1 "rm \$WORK/fx/gdmf.json" 'AT_RISK' 'os_version \(macOS 26.7.2, GDMF feed unreachable'
run_case "offline skips network checks" 1 "export UD_OFFLINE=1" 'HEALTHY' 'skipped: os_version \(offline\); network \(offline\)'
unset UD_OFFLINE
run_case "low disk is BLOCKED" 1 "sed -i '' 's/80000000000/9000000000/' \$WORK/fx/diskutil.txt" \
  '^<result>BLOCKED \| fail: disk_space \(only 9.0 GB free'
run_case "tight disk warns" 1 "sed -i '' 's/80000000000/20000000000/' \$WORK/fx/diskutil.txt" 'AT_RISK' 'disk_space \(20.0 GB free'
run_case "battery under 50 percent" 1 "printf \"Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t21%%; discharging\n\" > \$WORK/fx/pmset.txt" \
  'AT_RISK' 'power \(on battery at 21%'
run_case "some hosts unreachable" 1 "echo 'swcdn.apple.com mesu.apple.com' > \$WORK/fx/unreachable.txt" \
  'AT_RISK' 'network \(unreachable: swcdn.apple.com, mesu.apple.com\)'
run_case "no hosts reachable" 1 "echo 'gdmf.apple.com mesu.apple.com swscan.apple.com swcdn.apple.com swdist.apple.com updates.cdn-apple.com' > \$WORK/fx/unreachable.txt" \
  'BLOCKED' 'fail: network \(no Apple update host reachable\)'
run_case "bootstrap not escrowed (root)" 1 "printf 'Bootstrap Token supported on server: YES\nBootstrap Token escrowed to server: NO\n' > \$WORK/fx/bootstraptoken.txt" \
  'BLOCKED' 'bootstrap_token \(not escrowed'
run_case "server lacks bootstrap support" 1 "printf 'Bootstrap Token supported on server: NO\n' > \$WORK/fx/bootstraptoken.txt" \
  'AT_RISK' 'bootstrap_token \(MDM server does not report'
run_case "not root skips bootstrap" 0 "printf 'Bootstrap Token escrowed to server: NO\n' > \$WORK/fx/bootstraptoken.txt" \
  'HEALTHY' 'skipped: bootstrap_token \(needs root\)' '!fail'
run_case "not enrolled" 0 "printf 'Enrolled via DEP: No\nMDM enrollment: No\n' > \$WORK/fx/enrollment.txt" \
  'HEALTHY' 'not MDM enrolled' '!bootstrap_token'
run_case "enrolled but not approved" 1 "printf 'Enrolled via DEP: No\nMDM enrollment: Yes\n' > \$WORK/fx/enrollment.txt" \
  'AT_RISK' 'mdm_enrollment \(enrolled but not User Approved'
run_case "DDM persisted error gives the reason" 1 \
  "su_set DDMPersistedErrorKey -json '{\"count\":2,\"reason\":\"Software update failed.\",\"timestamp\":\"2026-11-01T18:30:32-06:00\"}'" \
  '^<result>BLOCKED \| fail: ddm_errors \(Software update failed. x2 at 2026-11-01T18:30:32-06:00\)'
run_case "empty DDM error record is fine" 1 "su_set DDMPersistedErrorKey -json '{}'" 'HEALTHY'
run_case "stale catalog scan" 1 "su_set LastSuccessfulDate -date 2026-10-01T00:00:00Z" 'AT_RISK' 'su_history \(last successful scan 34 days ago\)'
run_case "no scan recorded" 1 "/usr/bin/plutil -remove LastSuccessfulDate \$WORK/fx/SoftwareUpdate.plist" 'su_history \(no successful catalog scan'
run_case "custom catalog" 1 "su_set CatalogURL -string https://sus.example.com/index.sucatalog" 'AT_RISK' 'custom CatalogURL https://sus.example.com'
run_case "beta catalog is info only" 1 "su_set CatalogURL -string https://swscan.apple.com/content/catalogs/others/index-26beta-26.merged-1.sucatalog.gz" \
  'HEALTHY' 'beta catalog'
run_case "automatic updates off" 1 "su_set AutomaticDownload -bool false" 'HEALTHY' 'auto off: AutomaticDownload'
run_case "nonzero LastResultCode" 1 "su_set LastResultCode -integer 5" 'LastResultCode 5'
run_case "offered updates from cache" 1 \
  "su_set RecommendedUpdates -json '[{\"Display Name\":\"macOS Tahoe 26.8\",\"Display Version\":\"26.8\"},{\"Display Name\":\"Safari\",\"Display Version\":\"27.2\"}]'" \
  'offered: macOS Tahoe 26.8, Safari 27.2'
run_case "managed deferral" 1 \
  "/usr/bin/plutil -create xml1 \$WORK/fx/applicationaccess.plist; /usr/bin/plutil -insert forceDelayedSoftwareUpdates -bool true \$WORK/fx/applicationaccess.plist; /usr/bin/plutil -insert enforcedSoftwareUpdateMinorOSDeferredInstallDelay -integer 14 \$WORK/fx/applicationaccess.plist" \
  'HEALTHY' 'deferral: minor 14d'
run_case "install log failures in last 7 days" 1 \
  "printf '2026-11-03 09:44:24-06 Mac softwareupdated[2]: SUOSUErrorDomain Code=1 install failed: not enough space\n2026-10-01 09:00:00-06 Mac softwareupdated[3]: Install failed old\n' >> \$WORK/fx/install.log" \
  'AT_RISK' 'install_log \(1 failure line\(s\) in 7 days, last: 2026-11-03 09:44:24 SUOSUErrorDomain'
run_case "unreadable install log is skipped" 1 "rm \$WORK/fx/install.log" 'skipped: install_log'
run_case "unreadable SU prefs is skipped" 0 "rm \$WORK/fx/SoftwareUpdate.plist" 'su_history \(cannot read'
run_case "fail wins over warn, both listed" 1 \
  "sed -i '' 's/80000000000/9000000000/' \$WORK/fx/diskutil.txt; su_set CatalogURL -string https://sus.example.com/x" \
  '^<result>BLOCKED \| fail: disk_space .* \| warn: su_history'

echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
