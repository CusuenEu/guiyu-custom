#!/bin/zsh
set -e
cd "${0:A:h}"
mkdir -p 'dist/归屿.app/Contents/MacOS' 'dist/归屿.app/Contents/Resources'
logo_path='Design/SoftWorkspace/GuiyuCompanion.png'
if [[ -f "$logo_path" ]]; then
  if [[ -d Design/Guiyu-Icon-v1 && -f dist/AppIcon.icns && ! -f Design/Guiyu-Icon-v1/previous-AppIcon.icns ]]; then
    cp dist/AppIcon.icns Design/Guiyu-Icon-v1/previous-AppIcon.icns
  fi
  iconset_path='dist/GuiyuLogo.iconset'
  mkdir -p "$iconset_path"
  for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$logo_path" --out "$iconset_path/icon_${icon_size}x${icon_size}.png" >/dev/null
    retina_size=$((icon_size * 2))
    sips -z "$retina_size" "$retina_size" "$logo_path" --out "$iconset_path/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset_path" -o dist/AppIcon.icns
  cp "$logo_path" 'dist/归屿.app/Contents/Resources/GuiyuLogo.png'
fi
cp Design/SoftWorkspace/GuiyuCompanion.png 'dist/归屿.app/Contents/Resources/GuiyuCompanion.png'
swift build -c release --product Guiyu --jobs 4
binary_path=$(swift build -c release --show-bin-path)
cp "$binary_path/Guiyu" 'dist/归屿.app/Contents/MacOS/Guiyu'
mkdir -p 'dist/归屿.app/Contents/Frameworks'
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework 'dist/归屿.app/Contents/Frameworks/Sparkle.framework'
cp -f .build/artifacts/sparkle/Sparkle/LICENSE 'dist/归屿.app/Contents/Resources/Sparkle-LICENSE.txt'
if [[ -d "$binary_path/GRDB_GRDB.bundle" ]]; then
  ditto "$binary_path/GRDB_GRDB.bundle" 'dist/归屿.app/Contents/Resources/GRDB_GRDB.bundle'
fi
cp -f .build/checkouts/GRDB.swift/LICENSE 'dist/归屿.app/Contents/Resources/GRDB-LICENSE.txt' 
cat > 'dist/归屿.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Guiyu</string><key>CFBundleIdentifier</key><string>local.guiyu.workspace</string><key>CFBundleName</key><string>归屿</string><key>CFBundleDisplayName</key><string>归屿</string><key>CFBundleShortVersionString</key><string>0.5.0</string><key>CFBundleVersion</key><string>12</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleInfoDictionaryVersion</key><string>6.0</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>NSHighResolutionCapable</key><true/><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Merge Resources/FinderServices.plist' 'dist/归屿.app/Contents/Info.plist'
if [[ -f dist/AppIcon.icns ]]; then
cp dist/AppIcon.icns 'dist/归屿.app/Contents/Resources/AppIcon.icns'
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' 'dist/归屿.app/Contents/Info.plist'
fi
python3 - <<'UPDATE_PLIST'
import plistlib
from pathlib import Path
p = Path('dist/归屿.app/Contents/Info.plist')
data = plistlib.loads(p.read_bytes())
key = Path('Release/update-public-key.txt').read_text().strip()
import base64
assert len(base64.b64decode(key,validate=True)) == 32
# Forks must use their own feed and signing key before distributing updates.
data.update(SUFeedURL='https://github.com/tiduse1988/guiyu/releases/latest/download/appcast.xml',
    SUPublicEDKey=key, SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
    SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True,
    SUEnableSystemProfiling=False, SUScheduledCheckInterval=86400)
p.write_bytes(plistlib.dumps(data))
UPDATE_PLIST
codesign --force --deep --sign - 'dist/归屿.app'
codesign --verify --deep --strict 'dist/归屿.app' 
'dist/归屿.app/Contents/MacOS/Guiyu' --self-test
