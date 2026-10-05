#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Usage: %s VERSION\nExample: %s 0.1.0\n' "$0" "$0" >&2
    exit 2
fi

build_number="${PHELSUMA_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
    printf 'PHELSUMA_BUILD_NUMBER must contain digits only.\n' >&2
    exit 2
fi

case "$(uname -m)" in
    arm64) architecture="arm64" ;;
    x86_64) architecture="x86_64" ;;
    *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    scripts/test.sh
fi

PHELSUMA_VERSION="$version" PHELSUMA_BUILD_NUMBER="$build_number" \
    scripts/build-app.sh release

app_path="$PWD/build/Phelsuma.app"
dist_dir="$PWD/dist"
archive_name="Phelsuma-${version}-macOS-${architecture}.zip"
archive_path="$dist_dir/$archive_name"
checksum_path="$archive_path.sha256"

mkdir -p "$dist_dir"
rm -f "$archive_path" "$checksum_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
unzip -tq "$archive_path"
(
    cd "$dist_dir"
    shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

printf '\nRelease package created:\n  %s\n  %s\n' "$archive_path" "$checksum_path"
printf '\nThis build is ad-hoc signed and not notarized. Gatekeeper may require users to approve it manually.\n'
