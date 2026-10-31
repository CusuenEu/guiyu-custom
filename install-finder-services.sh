#!/bin/zsh
set -e
cd "${0:A:h}"
app_path="${PWD}/dist/归屿.app"
[[ -d "$app_path" ]] || { print -u2 '请先运行 ./build.sh'; exit 1; }
/usr/bin/plutil -extract NSServices xml1 -o /dev/null "$app_path/Contents/Info.plist"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
/System/Library/CoreServices/pbs -update
print '已刷新归屿的 Finder 系统服务注册。'
