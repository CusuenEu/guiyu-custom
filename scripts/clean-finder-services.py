#!/usr/bin/env python3
"""Unregister Guiyu test copies, retaining one installed service provider.

Dry-run by default. No bundles, preferences or other apps are deleted.
"""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys

LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def candidates(dump, keep):
    result = []
    for block in re.split(r'^-{20,}\s*$', dump, flags=re.M):
        identifier = re.search(r'^identifier:\s+(\S+)', block, re.M)
        path = re.search(r'^path:\s+(.+?)\s+\(0x[0-9a-f]+\)\s*$', block, re.M)
        if not identifier or not path or not identifier[1].startswith('local.guiyu.'):
            continue
        value = path[1]
        if Path(value).resolve() != keep.resolve() and value not in result:
            result.append(value)
    return result


def main():
    default = Path('/Applications/归屿.app')
    if not default.exists():
        default = Path.home() / 'Applications/归屿.app'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keep', type=Path, default=default)
    parser.add_argument('--apply', action='store_true', help='执行注销并刷新服务；默认仅预览')
    args = parser.parse_args()
    keep = args.keep.resolve()
    roots = [Path('/Applications'), Path.home() / 'Applications']
    if not any(keep.is_relative_to(root.resolve()) for root in roots):
        parser.error('只保留安装在系统或用户“应用程序”目录中的正式版')
    info = plistlib.loads((keep / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.guiyu.workspace' or not info.get('NSServices'):
        parser.error('保留目标不是提供 Finder 服务的归屿正式版')
    dump = subprocess.check_output([LSREGISTER, '-dump'], text=True)
    paths = candidates(dump, keep)
    print('保留：' + str(keep))
    for path in paths:
        print(('注销：' if args.apply else '将注销：') + path)
        if args.apply:
            result = subprocess.run([LSREGISTER, '-u', path], capture_output=True, text=True)
            if result.returncode:
                # Removed/unmounted disk images can leave unscannable LS rows.
                # Still refresh the installed provider and service cache.
                print('未能注销旧缓存：' + path + '\n' + (result.stderr + result.stdout).strip(), file=sys.stderr)
    if args.apply:
        subprocess.run([LSREGISTER, '-f', str(keep)], check=True)
        subprocess.run(['/System/Library/CoreServices/pbs', '-update'], check=True)
        print('已刷新归屿服务。关闭并重新打开 Finder 右键菜单即可。')
    else:
        print('仅预览；加 --apply 才会执行。不删除任何应用或资料。')


if __name__ == '__main__':
    main()
