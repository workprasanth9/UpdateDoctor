#!/bin/bash
# UpdateDoctor standalone Jamf Pro Extension Attribute (pure bash, no binary needed).
#
# Jamf Pro: Settings > Computer management > Extension attributes > New.
#   Data type: String. Input type: Script. Paste this file.
#
# Prints one <result>...</result> line, for example:
#   <result>BLOCKED | fail: ddm_errors (Software update failed. at 2026-11-01T18:30:32-06:00) | warn: os_version (26.7 behind 26.7.2) | skipped: bootstrap_token (needs root) | ud-sh 1.2.0</result>
#
# Verdicts match the updatedoctor CLI: BLOCKED (a check failed), AT_RISK (a warning),
# HEALTHY (nothing failed or warned). Jamf runs EAs as root. Without root the
# Bootstrap Token check is skipped and says so.
#
# Optional environment variables (for testing or manual runs; Jamf sets none):
#   UD_OFFLINE=1     skip network checks (GDMF feed, Apple host reachability)
#   UD_FIXTURES=dir  read recorded command output and files from dir instead of the Mac
#   UD_NOW=epoch     pretend the current time is this Unix time (fixture tests)
#   UD_AS_ROOT=0|1   override the root detection (fixture tests)
#
# Bash 3.2 compatible. Read only: it changes nothing on the Mac.

UD_SH_VERSION="1.2.0"
SU_PREFS="/Library/Preferences/com.apple.SoftwareUpdate.plist"
MANAGED_SU="/Library/Managed Preferences/com.apple.SoftwareUpdate.plist"
MANAGED_RESTRICTIONS="/Library/Managed Preferences/com.apple.applicationaccess.plist"
INSTALL_LOG="/var/log/install.log"
GDMF_URL="https://gdmf.apple.com/v2/pmv"
APPLE_HOSTS="gdmf.apple.com mesu.apple.com swscan.apple.com swcdn.apple.com swdist.apple.com updates.cdn-apple.com"
DISK_FAIL=15000000000
DISK_WARN=25000000000

TMP_DIR=$(mktemp -d /tmp/updatedoctor-ea.XXXXXX) || exit 0
trap 'rm -rf "$TMP_DIR"' EXIT

if [ -n "${UD_AS_ROOT:-}" ]; then IS_ROOT="$UD_AS_ROOT"
elif [ "$(id -u)" -eq 0 ]; then IS_ROOT=1
else IS_ROOT=0; fi
NOW="${UD_NOW:-$(date +%s)}"

FAILS=""
WARNS=""
SKIPS=""
add_fail() { FAILS="${FAILS:+$FAILS; }$1 ($2)"; }
add_warn() { WARNS="${WARNS:+$WARNS; }$1 ($2)"; }
add_skip() { SKIPS="${SKIPS:+$SKIPS; }$1 ($2)"; }

# cmd NAME COMMAND...: run COMMAND, or print $UD_FIXTURES/NAME.txt when fixtures are set.
# A missing fixture behaves like a command that could not run (exit 127).
cmd() {
  local name="$1"; shift
  if [ -n "${UD_FIXTURES:-}" ]; then
    [ -f "$UD_FIXTURES/$name.txt" ] || return 127
    cat "$UD_FIXTURES/$name.txt"
    return 0
  fi
  "$@" 2>/dev/null
}

# path REAL FIXTURE_NAME: the file to read, real or fixture.
path() {
  if [ -n "${UD_FIXTURES:-}" ]; then echo "$UD_FIXTURES/$2"; else echo "$1"; fi
}

# plist_get FILE KEYPATH: raw value of a plist or JSON key, empty if missing.
# Some macOS versions (seen on 15) print plutil errors to stdout, so only use output on success.
plist_get() {
  local v
  v=$(/usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null) || return 1
  printf '%s' "$v"
}

# plist_json FILE KEYPATH: value as JSON, empty if missing.
plist_json() {
  local v
  v=$(/usr/bin/plutil -extract "$2" json -o - "$1" 2>/dev/null) || return 1
  printf '%s' "$v"
}

# ver_lt A B: true if dotted version A is lower than B.
ver_lt() {
  local a="$1" b="$2" x y i=1
  while [ $i -le 4 ]; do
    x=$(echo "$a" | cut -d. -f$i); y=$(echo "$b" | cut -d. -f$i)
    x=${x:-0}; y=${y:-0}
    case "$x$y" in *[!0-9]*) x=0; y=0 ;; esac
    [ "$x" -lt "$y" ] && return 0
    [ "$x" -gt "$y" ] && return 1
    i=$((i + 1))
  done
  return 1
}

# iso_to_epoch 2026-11-04T15:44:19Z
iso_to_epoch() { date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null; }

# Root certificates from the System keychain, so curl trusts gdmf.apple.com
# (Apple signs it with a CA that is not in curl's default bundle).
CA_FILE="$TMP_DIR/roots.pem"
make_ca() {
  [ -s "$CA_FILE" ] && return 0
  /usr/bin/security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > "$CA_FILE" 2>/dev/null
}

# 1. macOS version against Apple's GDMF feed
check_os_version() {
  local sw ver build devices feed n i v latest="" sup newer=""
  sw=$(cmd sw_vers /usr/bin/sw_vers) || { add_fail os_version "could not read sw_vers"; return; }
  ver=$(echo "$sw" | awk -F':[ \t]*' '/^ProductVersion/ {print $2}')
  build=$(echo "$sw" | awk -F':[ \t]*' '/^BuildVersion/ {print $2}')
  OS_VERSION="$ver ($build)"
  if [ "${UD_OFFLINE:-0}" = 1 ]; then add_skip os_version "offline"; return; fi
  devices=$(cmd ioreg /usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice \
    | sed -nE 's/.*"target-type" = <"([^"]*)">.*/\1AP/p; s/.*"board-id" = <"([^"]*)">.*/\1/p' | tr -d '\000')
  feed="$TMP_DIR/gdmf.json"
  if [ -n "${UD_FIXTURES:-}" ]; then
    cp "$UD_FIXTURES/gdmf.json" "$feed" 2>/dev/null
  else
    make_ca
    /usr/bin/curl -s -m 20 --cacert "$CA_FILE" -o "$feed" "$GDMF_URL" 2>/dev/null
  fi
  n=$(plist_get "$feed" PublicAssetSets.macOS)
  case "$n" in ''|*[!0-9]*) add_warn os_version "macOS $ver, GDMF feed unreachable or unreadable, check gdmf.apple.com and TLS inspection"; return ;; esac
  local major="${ver%%.*}"
  i=0
  while [ $i -lt "$n" ]; do
    v=$(plist_get "$feed" "PublicAssetSets.macOS.$i.ProductVersion")
    sup=$(plist_json "$feed" "PublicAssetSets.macOS.$i.SupportedDevices")
    local match=0 d
    if [ -z "$devices" ]; then match=1; fi
    for d in $devices; do
      if echo "$sup" | grep -qi "\"$d\""; then match=1; fi
    done
    if [ $match = 1 ]; then
      if [ "${v%%.*}" = "$major" ]; then
        if [ -z "$latest" ] || ver_lt "$latest" "$v"; then latest="$v"; fi
      elif [ "${v%%.*}" -gt "$major" ] 2>/dev/null; then
        if [ -z "$newer" ] || ver_lt "$newer" "$v"; then newer="$v"; fi
      fi
    fi
    i=$((i + 1))
  done
  if [ -z "$latest" ]; then return; fi
  if ver_lt "$ver" "$latest"; then
    add_warn os_version "$ver behind $latest${newer:+, macOS $newer also supported}"
  fi
}

# 2. Updates the Mac already found (cached by softwareupdated, no slow scan)
check_pending() {
  local f
  f=$(path "$SU_PREFS" SoftwareUpdate.plist)
  [ -r "$f" ] || return
  local i=0 n name v names=""
  n=$(plist_get "$f" RecommendedUpdates)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  while [ $i -lt "$n" ]; do
    name=$(plist_get "$f" "RecommendedUpdates.$i.Display Name")
    v=$(plist_get "$f" "RecommendedUpdates.$i.Display Version")
    case "$name" in *"$v"*) v="" ;; esac
    names="${names:+$names, }$name${v:+ $v}"
    i=$((i + 1))
  done
  PENDING="$names"
}

# 3. Free space in the APFS container
check_disk() {
  local free gb
  cmd diskutil /usr/sbin/diskutil info -plist / > "$TMP_DIR/disk.plist"
  free=$(plist_get "$TMP_DIR/disk.plist" APFSContainerFree)
  case "$free" in ''|*[!0-9]*) add_skip disk_space "diskutil unreadable"; return ;; esac
  gb=$(awk -v b="$free" 'BEGIN { printf "%.1f GB", b / 1000000000 }')
  if [ "$free" -lt $DISK_FAIL ]; then add_fail disk_space "only $gb free, updates commonly fail below about 15 GB"
  elif [ "$free" -lt $DISK_WARN ]; then add_warn disk_space "$gb free, tight for a full update"; fi
}

# 4. Power
check_power() {
  local out pct
  out=$(cmd pmset /usr/bin/pmset -g batt) || { add_skip power "pmset unavailable"; return; }
  echo "$out" | grep -q "'AC Power'" && return
  pct=$(echo "$out" | grep -oE '[0-9]{1,3}%' | head -1 | tr -d '%')
  [ -z "$pct" ] && return
  if [ "$pct" -lt 50 ]; then add_warn power "on battery at ${pct}%, install may wait for power"; fi
}

# 5. Apple update hosts
check_network() {
  local h bad="" total=0 nbad=0 code
  if [ "${UD_OFFLINE:-0}" = 1 ]; then add_skip network "offline"; return; fi
  if [ -n "${UD_FIXTURES:-}" ]; then
    bad=$(cat "$UD_FIXTURES/unreachable.txt" 2>/dev/null)
    for h in $APPLE_HOSTS; do total=$((total + 1)); done
    for h in $bad; do nbad=$((nbad + 1)); done
  else
    make_ca
    for h in $APPLE_HOSTS; do
      total=$((total + 1))
      code=$(/usr/bin/curl -s -o /dev/null -I -m 8 --cacert "$CA_FILE" -w '%{http_code}' "https://$h/" 2>/dev/null)
      if [ -z "$code" ] || [ "$code" = "000" ]; then bad="$bad $h"; nbad=$((nbad + 1)); fi
    done
  fi
  [ $nbad -eq 0 ] && return
  bad="${bad# }"; bad="${bad// /, }"
  if [ $nbad -eq $total ]; then add_fail network "no Apple update host reachable"
  else add_warn network "unreachable: $bad"; fi
}

# 6 and 7. MDM enrollment and Bootstrap Token
check_mdm() {
  local out bt
  MDM=0
  out=$(cmd enrollment /usr/bin/profiles status -type enrollment) || { add_skip mdm_enrollment "profiles unavailable"; return; }
  if echo "$out" | grep -qiE '^MDM enrollment:.*yes'; then MDM=1; fi
  if [ $MDM = 1 ] && ! echo "$out" | grep -qiE '^Enrolled via DEP:.*yes' && ! echo "$out" | grep -qi 'user approved'; then
    add_warn mdm_enrollment "enrolled but not User Approved or ADE"
  fi
  if [ $MDM = 0 ]; then return; fi
  if [ "$IS_ROOT" != 1 ]; then add_skip bootstrap_token "needs root"; return; fi
  bt=$(cmd bootstraptoken /usr/bin/profiles status -type bootstraptoken) || { add_skip bootstrap_token "profiles unavailable"; return; }
  if echo "$bt" | grep -qiE 'supported on server:.*no'; then add_warn bootstrap_token "MDM server does not report Bootstrap Token support"
  elif ! echo "$bt" | grep -qiE 'escrowed to server:.*yes'; then add_fail bootstrap_token "not escrowed, Apple silicon needs it for unattended updates"; fi
}

# 8 to 10. Software Update preferences: DDM errors, scan history, catalog, automatic settings
check_su_prefs() {
  local f m reason ts count last code url days epoch key off="" val
  f=$(path "$SU_PREFS" SoftwareUpdate.plist)
  if [ ! -r "$f" ]; then add_skip su_history "cannot read $SU_PREFS"; return; fi

  # Read the fields directly; extracting the whole dictionary as JSON is not reliable on every macOS.
  reason=$(plist_get "$f" DDMPersistedErrorKey.reason)
  ts=$(plist_get "$f" DDMPersistedErrorKey.timestamp)
  count=$(plist_get "$f" DDMPersistedErrorKey.count)
  if [ -n "$reason$ts$count" ]; then
    add_fail ddm_errors "${reason:-error recorded}${count:+ x$count}${ts:+ at $ts}"
  fi

  last=$(plist_get "$f" LastSuccessfulDate)
  epoch=$(iso_to_epoch "$last")
  if [ -z "$epoch" ]; then add_warn su_history "no successful catalog scan recorded"
  else
    days=$(( (NOW - epoch) / 86400 ))
    if [ $days -gt 7 ]; then add_warn su_history "last successful scan $days days ago"; fi
  fi
  code=$(plist_get "$f" LastResultCode)
  LAST_RESULT="$code"
  url=$(plist_get "$f" CatalogURL)
  m=$(path "$MANAGED_SU" ManagedSoftwareUpdate.plist)
  if [ -z "$url" ] && [ -r "$m" ]; then url=$(plist_get "$m" CatalogURL); fi
  case "$url" in
    '') ;;
    *swscan.apple.com*beta*) BETA=1 ;;
    *swscan.apple.com*) ;;
    *) add_warn su_history "custom CatalogURL $url" ;;
  esac

  for key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates; do
    val=""
    [ -r "$m" ] && val=$(plist_get "$m" "$key")
    [ -z "$val" ] && val=$(plist_get "$f" "$key")
    [ "$val" = "false" ] && off="${off:+$off, }$key"
  done
  AUTO_OFF="$off"
}

# FileVault (informational: unattended restarts then need a Bootstrap Token or a user)
check_filevault() {
  local out
  out=$(cmd fdesetup /usr/bin/fdesetup status) || return
  echo "$out" | grep -q "FileVault is On" && FILEVAULT=1
}

# 11. Managed deferral
check_deferral() {
  local r d=""
  r=$(path "$MANAGED_RESTRICTIONS" applicationaccess.plist)
  [ -r "$r" ] || return
  [ "$(plist_get "$r" forceDelayedSoftwareUpdates)" = "true" ] && d="minor $(plist_get "$r" enforcedSoftwareUpdateMinorOSDeferredInstallDelay)d"
  [ "$(plist_get "$r" forceDelayedMajorSoftwareUpdates)" = "true" ] && d="${d:+$d, }major $(plist_get "$r" enforcedSoftwareUpdateMajorOSDeferredInstallDelay)d"
  DEFERRAL="$d"
}

# 12. Install log evidence: recent softwareupdated install failures (last 7 days)
check_install_log() {
  local f since lines n last
  f=$(path "$INSTALL_LOG" install.log)
  [ -r "$f" ] || { add_skip install_log "cannot read install.log"; return; }
  since=$(date -j -r $((NOW - 7 * 86400)) +%Y-%m-%d)
  lines=$(tail -n 200000 "$f" | awk -v s="$since" '$1 >= s' \
    | grep -E 'softwareupdated|SoftwareUpdate|installd' \
    | grep -iE 'install(ation)? failed|failed to (install|prepare|apply|download)|SUOSUErrorDomain|MobileSoftwareUpdateErrorDomain|update failed' )
  n=$(printf '%s' "$lines" | grep -c . )
  [ "$n" -eq 0 ] && return
  last=$(echo "$lines" | tail -1 | sed -E 's/^([0-9-]+ [0-9:]+)[^:]*: /\1 /' | cut -c1-160)
  add_warn install_log "$n failure line(s) in 7 days, last: $last"
}

OS_VERSION="" PENDING="" LAST_RESULT="" BETA=0 AUTO_OFF="" DEFERRAL="" MDM=0 FILEVAULT=0
check_os_version
check_pending
check_disk
check_power
check_network
check_mdm
check_su_prefs
check_filevault
check_deferral
check_install_log

if [ -n "$FAILS" ]; then VERDICT="BLOCKED"
elif [ -n "$WARNS" ]; then VERDICT="AT_RISK"
else VERDICT="HEALTHY"; fi

OUT="$VERDICT"
[ -n "$FAILS" ] && OUT="$OUT | fail: $FAILS"
[ -n "$WARNS" ] && OUT="$OUT | warn: $WARNS"
INFO="macOS $OS_VERSION"
[ -n "$PENDING" ] && INFO="$INFO, offered: $PENDING"
[ "$FILEVAULT" = 1 ] && INFO="$INFO, FileVault on"
[ "$BETA" = 1 ] && INFO="$INFO, beta catalog"
[ -n "$AUTO_OFF" ] && INFO="$INFO, auto off: $AUTO_OFF"
[ -n "$DEFERRAL" ] && INFO="$INFO, deferral: $DEFERRAL"
[ -n "$LAST_RESULT" ] && [ "$LAST_RESULT" != 0 ] && INFO="$INFO, LastResultCode $LAST_RESULT"
[ "$MDM" = 0 ] && INFO="$INFO, not MDM enrolled"
OUT="$OUT | info: $INFO"
[ -n "$SKIPS" ] && OUT="$OUT | skipped: $SKIPS"
OUT="$OUT | ud-sh $UD_SH_VERSION"
# Jamf stores the whole string; keep it short and on one line.
OUT=$(printf '%s' "$OUT" | tr '\n<>' '   ' | cut -c1-1000)
echo "<result>$OUT</result>"
exit 0
