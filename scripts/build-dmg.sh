#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="${1:-dist/归屿.app}"
[[ -d "$app" ]] || { print -u2 'Application bundle not found'; exit 1; }
app="${app:A}"
asset=$(/usr/libexec/PlistBuddy -c 'Print :GuiyuReleaseAsset' "$app/Contents/Info.plist")
output="${2:-dist/${asset%.zip}.dmg}"
output="${output:A}"
codesign --verify --deep --strict "$app"
tools='.build/dmg-tools'
if [[ ! -x "$tools/bin/python" ]]; then
  python3 -m venv "$tools"
fi
if ! "$tools/bin/python" -c 'import dmgbuild, ds_store, mac_alias' >/dev/null 2>&1; then
  "$tools/bin/python" -m pip install -r scripts/dmg-requirements.txt
fi
work=$(mktemp -d -t GuiyuDMG)
trap 'rm -rf "$work"' EXIT
swift scripts/dmg-background.swift "$work/background.tiff"
mkdir -p "${output:h}"
"$tools/bin/python" -m dmgbuild -s scripts/dmg-settings.py -D "app=$app" -D "background=$work/background.tiff" '归屿安装' "$work/installer.dmg"
hdiutil verify "$work/installer.dmg"
mv "$work/installer.dmg" "$output"
print "Mac installer: $output"
