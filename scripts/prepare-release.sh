#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app='dist/归屿.app'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
tag=$(/usr/libexec/PlistBuddy -c 'Print :GuiyuReleaseTag' "$app/Contents/Info.plist")
asset=$(/usr/libexec/PlistBuddy -c 'Print :GuiyuReleaseAsset' "$app/Contents/Info.plist")
python3 - "$app/Contents/Info.plist" <<'SERVICES'
import plistlib, sys
info = plistlib.load(open(sys.argv[1], 'rb'))
if {s.get('NSMessage') for s in info.get('NSServices', [])} != {'smartNaming', 'quickArchive'}:
    raise SystemExit('开发构建未声明 Finder 服务；正式发布前请用 GUIYU_FINDER_SERVICES=1 ./build.sh 重建。')
SERVICES
[[ "$version" =~ '^[0-9]{8}\([0-9]{2}\)$' && "$tag" =~ '^v[0-9]{8}-[0-9]{2}$' ]] || { print -u2 'Invalid dated version'; exit 1; }
archive_dir="${GUIYU_RELEASE_OUTPUT_ROOT:-Release/archives}/${tag}"
mkdir -p "$archive_dir"
archive="${archive_dir}/${asset}"
lipo "$app/Contents/MacOS/Guiyu" -verify_arch arm64
codesign --verify --deep --strict "$app"
# ditto preserves framework symlinks and helper executable permissions.
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
# Keep the human installer out of feed discovery: Sparkle continues to receive
# the existing signed ZIP, with one unambiguous enclosure per release.
feed_dir=$(mktemp -d -t GuiyuFeed)
trap 'rm -rf "$feed_dir"' EXIT
ln "$archive" "$feed_dir/$asset"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account tiduse1988.guiyu \
  --download-url-prefix "https://github.com/tiduse1988/guiyu/releases/download/${tag}/" \
  --link 'https://github.com/tiduse1988/guiyu' --maximum-deltas 0 "$feed_dir"
cp "$feed_dir/appcast.xml" "$archive_dir/appcast.xml"
.build/artifacts/sparkle/Sparkle/bin/sign_update --account tiduse1988.guiyu --verify "$archive_dir/appcast.xml"
./scripts/build-dmg.sh "$app" "$archive_dir/${asset%.zip}.dmg"
(cd "$archive_dir" && shasum -a 256 "$asset" "${asset%.zip}.dmg" appcast.xml > SHA256SUMS.txt)
print "Release files: $archive_dir"
