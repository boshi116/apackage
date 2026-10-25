#!/bin/bash
set -euo pipefail

: "${GH_REPO:?}"
: "${RELEASE_TAG:?}"
: "${RELEASE_SHA:?}"

version=$(sed -n 's/^PKG_VERSION:=//p' Makefile)
revision=$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
case "$RELEASE_TAG" in
  "v$version"|"v$version-r$revision"|"release-$version-r$revision") ;;
  *) echo 'Release tag must match the package version in Makefile.' >&2; exit 1 ;;
esac

# Prevent a manual dispatch from attaching another commit's binaries to a tag.
tag_refs=$(gh api "repos/$GH_REPO/git/matching-refs/tags/$RELEASE_TAG" --jq '.[].ref')
if printf '%s\n' "$tag_refs" | grep -Fxq "refs/tags/$RELEASE_TAG"; then
  existing_sha=$(gh api "repos/$GH_REPO/commits/$RELEASE_TAG" --jq '.sha')
  if [ "$existing_sha" != "$RELEASE_SHA" ]; then
    echo 'The release tag points to a different commit. Select that tag as the workflow ref or use a new version.' >&2
    exit 1
  fi
fi

mkdir -p release-assets
find packages -type f \( -name '*.apk' -o -name '*.ipk' \) -exec cp -t release-assets -- {} +
cd release-assets
# Never publish a release with only one package format or no main package.
test -s "luci-app-argon-config-$version-r$revision.apk"
test -s "luci-app-argon-config_${version}-r${revision}_all.ipk"
mapfile -t assets < <(find . -maxdepth 1 -type f \( -name '*.apk' -o -name '*.ipk' \) -printf '%f\n' | sort)
sha256sum "${assets[@]}" > SHA256SUMS
assets+=(SHA256SUMS)

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
  gh release edit "$RELEASE_TAG" --draft=false --latest
else
  gh release create "$RELEASE_TAG" "${assets[@]}" --target "$RELEASE_SHA" \
    --title "$RELEASE_TAG" --generate-notes --latest
fi
