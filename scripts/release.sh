#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
if [[ -z "$version" ]]; then
  echo "Could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

dist="$root/dist"
archive="$dist/Vox.xcarchive"
app="$archive/Products/Applications/Vox.app"
zip_path="$dist/Vox.zip"

rm -rf "$dist"
mkdir -p "$dist"

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
xcodegen generate

build_settings=(
  -scheme Vox
  -configuration Release
  -destination 'generic/platform=macOS'
  -archivePath "$archive"
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=NO
)

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  build_settings+=(CODE_SIGN_IDENTITY="$DEVELOPER_ID")
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    build_settings+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi
fi

xcodebuild "${build_settings[@]}" archive

if [[ ! -d "$app" ]]; then
  echo "Archive did not contain Vox.app" >&2
  exit 1
fi

ditto -c -k --keepParent "$app" "$zip_path"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  profile="${NOTARY_PROFILE:-VoxNotary}"
  echo "Submitting $zip_path to Apple notarization (profile $profile)…"
  xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait
  xcrun stapler staple "$app"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$app" "$zip_path"
else
  echo "Notarization skipped (set DEVELOPER_ID to sign and notarize)."
  echo "An ad-hoc zip needs right-click → Open the first time."
fi

echo "Wrote $zip_path (Vox $version, arm64)"

if [[ "${SKIP_GH_RELEASE:-}" == "1" ]]; then
  echo "GitHub Release skipped (SKIP_GH_RELEASE=1)."
  exit 0
fi

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  tag="v$version"
  notes="$(cat <<EOF
Menu-bar Mac app. Download Vox.zip, move Vox.app to Applications, and open it.

Requires macOS 14 or later on Apple Silicon. Models download after you press Use in Models….
EOF
)"
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$zip_path" --clobber
    echo "Uploaded $zip_path to existing GitHub Release $tag"
  else
    gh release create "$tag" "$zip_path" --title "Vox $version" --notes "$notes"
    echo "Created GitHub Release $tag"
  fi
else
  echo "gh is not authenticated. Attach $zip_path to a GitHub Release by hand."
fi
