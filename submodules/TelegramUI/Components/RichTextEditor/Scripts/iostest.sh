#!/bin/bash
# Runs the package's iOS-simulator tests. $1 = optional -only-testing filter
# (e.g. RichTextEditorUIKitTests/MapperTests). Set SCHEME/DEVICE env to override.
set -o pipefail
SCHEME="${SCHEME:-RichTextEditor-Package}"
DEVICE="${DEVICE:-CA0A2186-0F4A-425B-B3B1-9B61E5FF01A9}"  # controller tweak (uncommitted): iPhone 17 Pro K1 by UDID (the bare name 'iPhone 17 Pro' collides with 7 sims → ambiguous destination)
FILTER=""
[ -n "$1" ] && FILTER="-only-testing:$1"
xcodebuild test -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$DEVICE" $FILTER 2>&1 \
  | grep -E "Test Case .*(passed|failed)|error:|BUILD (SUCCEEDED|FAILED)|Executed [0-9]+ test"
