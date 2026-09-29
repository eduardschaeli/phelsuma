#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
# Some Command Line Tools releases ship Swift Testing but omit its search paths.
dev_path="$(xcode-select -p)"
test_flags=()
if [[ "$dev_path" == */CommandLineTools && -d "$dev_path/Library/Developer/Frameworks/Testing.framework" ]]; then
    test_flags=(-Xswiftc "-F$dev_path/Library/Developer/Frameworks"
                -Xlinker -rpath -Xlinker "$dev_path/Library/Developer/Frameworks"
                -Xlinker -rpath -Xlinker "$dev_path/Library/Developer/usr/lib"
                -Xswiftc -plugin-path -Xswiftc "$dev_path/usr/lib/swift/host/plugins/testing")
fi
swift test --disable-sandbox --cache-path .build/swift-cache "${test_flags[@]}" "$@"
