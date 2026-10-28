#!/bin/bash
# Jamf Pro Extension Attribute: UpdateDoctor verdict.
# Data type: String. Input type: Script.
# Result examples: HEALTHY, AT_RISK: os_version, power, BLOCKED: bootstrap_token
# Uses --quick so inventory is not slowed down by `softwareupdate -l`.
BIN="/usr/local/bin/updatedoctor"
[[ -x "$BIN" ]] || BIN="/opt/homebrew/bin/updatedoctor"
if [[ ! -x "$BIN" ]]; then
  echo "<result>NOT_INSTALLED</result>"
  exit 0
fi
"$BIN" doctor --ea --quick
exit 0
