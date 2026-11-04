#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product Explorer
BIN_DIR="$(swift build --show-bin-path)"
APP_SOURCES=(Sources/Pathfind/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Pathfind/main.swift})
swiftc -swift-version 5 -I "$BIN_DIR/Modules" \
    "${APP_SOURCES[@]}" Tests/NativeChecks/*.swift \
    "$BIN_DIR"/PathfindCore.build/*.swift.o -o "$BIN_DIR/PathfindNativeChecks"
"$BIN_DIR/PathfindNativeChecks"
