#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-ai-bg-runtime}"
VERSION="${2:-1.0.0}"
REPO="${3:-iordv/Droppy}"
TEAM_ID="${4:-NARHG44L48}"
SIGNING_IDENTITY="${5:-Developer ID Application: Jordy Spruit (NARHG44L48)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/Runtimes/AIBackgroundRemovalRuntime"
ARTIFACTS_DIR="$ROOT_DIR/.runtime-artifacts/ai-bg-runtime/$VERSION"

mkdir -p "$ARTIFACTS_DIR"

resolve_binary_path() {
    local arch="$1"
    find "$PKG_DIR/.build" -type f -name droppy-ai-bg-runtime \
        | rg "/${arch}-apple-macosx.*/release/" \
        | rg -v "\\.dSYM/" \
        | head -n 1
}

build_arch() {
    local arch="$1"
    local out_dir="$ARTIFACTS_DIR/$arch"
    local runtime_dir="$out_dir/ai-bg-runtime"
    local tar_path="$ARTIFACTS_DIR/ai-bg-runtime-${arch}.tar.gz"

    rm -rf "$out_dir"
    mkdir -p "$runtime_dir"

    swift build --package-path "$PKG_DIR" --configuration release --arch "$arch" --product droppy-ai-bg-runtime >&2

    local built_binary
    built_binary="$(resolve_binary_path "$arch")"
    if [[ -z "$built_binary" ]]; then
        echo "Failed to locate built helper for arch=$arch" >&2
        exit 1
    fi

    cp "$built_binary" "$runtime_dir/droppy-ai-bg-runtime"
    chmod +x "$runtime_dir/droppy-ai-bg-runtime"

    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$runtime_dir/droppy-ai-bg-runtime"

    local team_line
    team_line="$(codesign -dv --verbose=4 "$runtime_dir/droppy-ai-bg-runtime" 2>&1 | rg '^TeamIdentifier=' | head -n 1 || true)"
    if [[ "$team_line" != "TeamIdentifier=${TEAM_ID}" ]]; then
        echo "Unexpected TeamIdentifier for arch=$arch: ${team_line:-<missing>}" >&2
        exit 1
    fi

    tar -C "$out_dir" -czf "$tar_path" "ai-bg-runtime"

    local sha
    sha="$(shasum -a 256 "$tar_path" | awk '{print $1}')"
    local size
    size="$(stat -f%z "$tar_path")"

    echo "$arch|$sha|$size|$tar_path"
}

ensure_release() {
    if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
        gh release create "$TAG" -R "$REPO" --title "AI BG Runtime" --notes "External runtime artifacts for Droppy AI Background Removal."
    fi
}

remove_existing_assets() {
    local assets
    assets="$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name')"
    if [[ -z "$assets" ]]; then
        return
    fi

    while IFS= read -r asset; do
        [[ -z "$asset" ]] && continue
        case "$asset" in
            ai-bg-runtime-*.tar.gz|ai-bg-runtime-manifest.txt|ai-bg-runtime-manifest.json)
                gh release delete-asset "$TAG" "$asset" -R "$REPO" -y >/dev/null
                ;;
        esac
    done <<< "$assets"
}

printf 'Building runtime artifacts...\n'
arm_meta="$(build_arch arm64)"
x86_meta="$(build_arch x86_64)"

arm_sha="$(echo "$arm_meta" | cut -d'|' -f2)"
arm_size="$(echo "$arm_meta" | cut -d'|' -f3)"
arm_tar="$(echo "$arm_meta" | cut -d'|' -f4)"

x86_sha="$(echo "$x86_meta" | cut -d'|' -f2)"
x86_size="$(echo "$x86_meta" | cut -d'|' -f3)"
x86_tar="$(echo "$x86_meta" | cut -d'|' -f4)"

manifest_path="$ARTIFACTS_DIR/ai-bg-runtime-manifest.txt"
cat > "$manifest_path" <<MANIFEST
{
  "id": "aiBackgroundRemoval",
  "version": "$VERSION",
  "protocolVersion": 1,
  "minAppVersion": null,
  "executableName": "droppy-ai-bg-runtime",
  "artifacts": [
    {
      "arch": "arm64",
      "url": "https://github.com/${REPO}/releases/download/${TAG}/ai-bg-runtime-arm64.tar.gz",
      "sha256": "$arm_sha",
      "sizeBytes": $arm_size,
      "teamID": "$TEAM_ID"
    },
    {
      "arch": "x86_64",
      "url": "https://github.com/${REPO}/releases/download/${TAG}/ai-bg-runtime-x86_64.tar.gz",
      "sha256": "$x86_sha",
      "sizeBytes": $x86_size,
      "teamID": "$TEAM_ID"
    }
  ]
}
MANIFEST

ensure_release
remove_existing_assets

gh release upload "$TAG" "$manifest_path" "$arm_tar" "$x86_tar" -R "$REPO" --clobber

printf '\nPublished runtime artifacts to %s (%s)\n' "$REPO" "$TAG"
printf 'Manifest URL: https://github.com/%s/releases/download/%s/ai-bg-runtime-manifest.txt\n' "$REPO" "$TAG"
