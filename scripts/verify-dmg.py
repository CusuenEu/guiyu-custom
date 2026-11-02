#!/usr/bin/env python3
"""Verify the mounted installer and an isolated copy, without opening Finder."""
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from ds_store import DSStore

image = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='GuiyuDMGCheck-') as directory:
    root = Path(directory).resolve()
    mount = root / 'volume'
    mount.mkdir()
    result = subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse',
                                     '-noautoopen', '-mountpoint', str(mount), '-plist', str(image)])
    volume = next(entity for entity in plistlib.loads(result)['system-entities'] if entity.get('mount-point'))
    device = volume['dev-entry']
    try:
        assert Path(volume['mount-point']).resolve() == mount
        app = mount / '归屿.app'
        assert app.is_dir()
        assert (mount / '应用程序').is_symlink()
        assert os.readlink(mount / '应用程序') == '/Applications'
        assert (mount / '.background.tiff').is_file()
        with DSStore.open(str(mount / '.DS_Store'), 'r') as store:
            assert store['归屿.app']['Iloc'] == (180, 210)
            assert store['应用程序']['Iloc'] == (480, 210)
            view = store['.']['icvp']
            assert view['backgroundType'] == 2 and view['iconSize'] == 100
            assert store['.']['icvl'] == (b'type', b'icnv')
            assert store['.']['bwsp']['WindowBounds'] == '{{200, 160}, {660, 420}}'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert (app / 'Contents/Resources' / info['CFBundleIconFile']).is_file()
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        installed = root / 'Applications/归屿.app'
        installed.parent.mkdir()
        subprocess.run(['ditto', str(app), str(installed)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
        binary = 'Contents/MacOS/Guiyu'
        assert (installed / binary).read_bytes() == (app / binary).read_bytes()
        if '--self-test' in sys.argv:
            subprocess.run([sys.executable, str(Path(__file__).with_name('run-isolated-self-tests.py')), str(installed)], check=True)
        print('PASS: read-only DMG, real Applications link, native Finder layout, app icon, '
              'signature and isolated installation copy; version=' + info['CFBundleShortVersionString'])
    finally:
        subprocess.run(['hdiutil', 'detach', device], check=True)
print('DMG SHA256: ' + hashlib.sha256(image.read_bytes()).hexdigest())
