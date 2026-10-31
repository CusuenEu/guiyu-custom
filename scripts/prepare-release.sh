#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app='dist/归屿.app'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
tag=$(/usr/libexec/PlistBuddy -c 'Print :GuiyuReleaseTag' "$app/Contents/Info.plist")
asset=$(/usr/libexec/PlistBuddy -c 'Print :GuiyuReleaseAsset' "$app/Contents/Info.plist")
[[ "$version" =~ '^[0-9]{8}\([0-9]{2}\)$' && "$tag" =~ '^v[0-9]{8}-[0-9]{2}$' ]] || { print -u2 'Invalid dated version'; exit 1; }
archive_dir="Release/archives/${tag}"
mkdir -p "$archive_dir"
archive="${archive_dir}/${asset}"
lipo "$app/Contents/MacOS/Guiyu" -verify_arch arm64
codesign --verify --deep --strict "$app"
# ditto preserves framework symlinks and helper executable permissions.
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --account tiduse1988.guiyu \
  --download-url-prefix "https://github.com/tiduse1988/guiyu/releases/download/${tag}/" \
  --link 'https://github.com/tiduse1988/guiyu' --maximum-deltas 0 "$archive_dir"
.build/artifacts/sparkle/Sparkle/bin/sign_update --account tiduse1988.guiyu --verify "$archive_dir/appcast.xml"
(cd "$archive_dir" && shasum -a 256 "$asset" appcast.xml > SHA256SUMS.txt)
print "Release files: $archive_dir"
