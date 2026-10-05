#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
version="${version#v}"
mode="${2:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Usage: %s VERSION [--publish]\nExample: %s 0.1.0 --publish\n' "$0" "$0" >&2
    exit 2
fi
if [[ -n "$mode" && "$mode" != "--publish" ]]; then
    printf 'Unknown option: %s\nUsage: %s VERSION [--publish]\n' "$mode" "$0" >&2
    exit 2
fi

branch=""
if [[ "$mode" == "--publish" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        printf 'Publishing requires GitHub CLI. Install it with: brew install gh\nThen authenticate with: gh auth login\n' >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        printf 'GitHub CLI is not authenticated. Run: gh auth login\n' >&2
        exit 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        printf 'Refusing to publish from a dirty worktree. Commit or stash changes first.\n' >&2
        exit 1
    fi
    branch="$(git branch --show-current)"
    if [[ -z "$branch" ]]; then
        printf 'Refusing to publish from a detached HEAD. Check out the release branch first.\n' >&2
        exit 1
    fi
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

if [[ "$mode" == "--publish" ]]; then
    tag="v$version"
    git push origin "$branch"
    gh release create "$tag" "$archive_path" "$checksum_path" \
        --target "$branch" --title "Phelsuma $version" --generate-notes
    printf '\nPublished GitHub release %s.\n' "$tag"
fi
