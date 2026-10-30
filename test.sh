#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEVELOPER="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER/Library/Developer/Frameworks"
# Command Line Tools includes Swift Testing here, but SwiftPM's default
# framework search path currently assumes the full Xcode directory layout.
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xswiftc -load-plugin-library \
        -Xswiftc "$DEVELOPER/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS"
else
    swift test --disable-xctest
fi
