#!/bin/zsh
# Runs the unit tests. Works with only the Command Line Tools installed.
set -euo pipefail
cd "${0:A:h:h}"

FLAGS=()
CLT=/Library/Developer/CommandLineTools
if [[ "$(xcode-select -p)" == "$CLT"* ]]; then
    # The newest CLT SDK needs SwiftUI macros that ship only with Xcode; use the macOS 26 SDK.
    if [[ -z "${SDKROOT:-}" ]]; then
        for candidate in $CLT/SDKs/MacOSX26*.sdk(N); do
            export SDKROOT="$candidate"
        done
    fi
    # swift-build sometimes loses track of the Swift Testing macros after an edit; point at them.
    FLAGS=(-Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing")
fi
swift test "${FLAGS[@]}" "$@"
