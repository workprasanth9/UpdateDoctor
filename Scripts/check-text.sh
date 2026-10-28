#!/bin/bash
# Fails if any tracked text file contains an em dash (U+2014).
set -euo pipefail
cd "$(dirname "$0")/.."
EM_DASH=$(printf '\xe2\x80\x94')
if git ls-files -z | xargs -0 grep -n -I -F "$EM_DASH" -- 2>/dev/null; then
  echo "Em dashes are not allowed in this repository."
  exit 1
fi
echo "Text check passed."
